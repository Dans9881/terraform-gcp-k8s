#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
LOG_FILE="/var/log/startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== START PROVISIONING ==="

retry() {
  local retries=$1
  shift
  local count=0
  until "$@"; do
    exit_code=$?
    count=$((count+1))
    if [ $count -ge $retries ]; then
      echo "Failed: $*"
      return $exit_code
    fi
    echo "Retry $count/$retries..."
    sleep 5
  done
}

wait_resource() {
  local desc=$1
  local cmd=$2

  echo "=== WAIT $${desc} ==="
  for i in {1..60}; do
    if eval "$cmd" >/dev/null 2>&1; then
      echo "$${desc} READY"
      return 0
    fi
    echo "Waiting $${desc} ($i/60)..."
    sleep 5
  done

  echo "$${desc} TIMEOUT"
  return 1
}

echo "=== INSTALL DEPENDENCIES ==="
retry 5 apt update -y
retry 5 apt install -y curl git openssh-client ca-certificates

echo "=== INSTALL NGINX ==="
retry 5 apt update
retry 5 apt install -y nginx libnginx-mod-stream

echo "=== STOP NGINX (CLEAN STATE) ==="
systemctl stop nginx || true

echo "=== CLEAN OLD NGINX CONFIG ==="
rm -f /etc/nginx/sites-enabled/*
rm -f /etc/nginx/sites-available/*
rm -f /etc/nginx/conf.d/*

echo "=== CONFIG NGINX HTTP (TRAEFIK) ==="
cat <<EOF > /etc/nginx/conf.d/http-traefik.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location / {
        proxy_pass http://127.0.0.1:30080;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

echo "=== CLEAN OLD STREAM CONFIG ==="
sed -i '/stream {/,$d' /etc/nginx/nginx.conf

echo "=== CONFIG NGINX STREAM (HTTPS PASSTHROUGH) ==="
cat <<EOF >> /etc/nginx/nginx.conf

stream {
    upstream traefik_https {
        server 127.0.0.1:30443;
    }

    server {
        listen 443;
        proxy_pass traefik_https;
    }
}
EOF

echo "=== TEST NGINX ==="
nginx -t

echo "=== START NGINX ==="
systemctl restart nginx
systemctl enable nginx

echo "=== FIX HOSTNAME ==="
HOSTNAME=$(hostname)

if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi

echo "=== FIX NETWORK ==="
modprobe br_netfilter || true
modprobe overlay || true

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sysctl --system

echo "=== SETUP SSH ==="
mkdir -p /home/${ssh_user}/.ssh

cat <<EOF > /home/${ssh_user}/.ssh/id_ed25519
${private_key}
EOF

chmod 600 /home/${ssh_user}/.ssh/id_ed25519
chown -R ${ssh_user}:${ssh_user} /home/${ssh_user}/.ssh

echo "=== MASTER NODE ==="
if [ "${node_role}" = "master" ]; then

  echo "=== INSTALL K3S (NO CNI) ==="
  curl -sfL https://get.k3s.io | sh -s - \
    --disable traefik \
    --flannel-backend=none \
    --disable-network-policy \
    --disable-kube-proxy \
    --write-kubeconfig-mode 644

  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  echo "=== FIX KUBECONFIG ==="
  mkdir -p /home/${ssh_user}/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/${ssh_user}/.kube/config
  chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.kube/config
  chmod 600 /home/${ssh_user}/.kube/config

  wait_resource "API READY" "kubectl get --raw='/readyz'"
  wait_resource "NODE READY" "kubectl get nodes --no-headers | grep -q Ready"

  echo "=== TAINT MASTER NODE ==="
  MASTER_NODE=$(hostname)
  kubectl taint nodes $MASTER_NODE node-role.kubernetes.io/control-plane=true:NoSchedule --overwrite || true

  echo "=== INSTALL CILIUM CLI ==="
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/$${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
  tar xzvf cilium-linux-amd64.tar.gz
  mv cilium /usr/local/bin/
  rm cilium-linux-amd64.tar.gz

  echo "=== INSTALL CILIUM (CLEAN CONFIG) ==="
  cilium install \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=10.10.0.2 \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set tunnelProtocol=vxlan \
    --set securityContext.privileged=true \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8s.requireIPv4PodCIDR=true

  echo "=== WAIT CILIUM POD EXIST ==="
  wait_resource "CILIUM POD EXIST" \
    "kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -q ."

  echo "=== WAIT CILIUM READY ==="
  kubectl wait --for=condition=Ready pods \
    -n kube-system -l k8s-app=cilium \
    --timeout=300s || true

  echo "=== WAIT SYSTEM POD EXIST ==="
  wait_resource "SYSTEM POD EXIST" \
    "kubectl get pods -n kube-system --no-headers | grep -q ."

  echo "=== WAIT SYSTEM POD READY ==="
  kubectl wait --for=condition=Ready pods \
    -n kube-system --all --timeout=300s || true

  echo "=== VALIDATE DNS ==="
  DNS_OK=false
  for i in {1..40}; do
    if kubectl run dns-test --rm -i --restart=Never \
      --image=busybox:1.36 \
      -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
      echo "DNS OK"
      DNS_OK=true
      break
    fi
    echo "Waiting DNS ($i/40)..."
    sleep 5
  done

  if [ "$DNS_OK" = false ]; then
    echo "DNS FAILED"
    exit 1
  fi

  echo "=== CLUSTER HEALTH ==="
  kubectl get nodes
  kubectl get pods -A

  echo "=== INSTALL HELM ==="
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  echo "=== CLONE INFRA ==="
  mkdir -p /srv/k8s
  rm -rf /tmp/infra-k3s || true
  retry 5 git clone ${repo_url} /tmp/infra-k3s
  cp -r /tmp/infra-k3s/k8s/* /srv/k8s/
  cp /tmp/infra-k3s/deploy.sh /srv/k8s/
  rm -rf /tmp/infra-k3s
  cd /srv/k8s
  chmod +x deploy.sh

  echo "=== RUN DEPLOY ==="
  sudo -u ${ssh_user} KUBECONFIG=/etc/rancher/k3s/k3s.yaml bash /srv/k8s/deploy.sh

echo "=== WORKER NODE ==="
elif [ "${node_role}" = "worker" ]; then

  wait_resource "MASTER API" "curl -k https://${master_ip}:6443"

  echo "=== GET TOKEN ==="
  for i in {1..60}; do
    TOKEN=$(ssh -i /home/${ssh_user}/.ssh/id_ed25519 \
      -o StrictHostKeyChecking=no \
      ${ssh_user}@${master_ip} \
      "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null || true)

    [ -n "$TOKEN" ] && break
    sleep 5
  done

  if [ -z "$${TOKEN:-}" ]; then
    echo "Failed get token"
    exit 1
  fi

  echo "=== JOIN WORKER ==="
  curl -sfL https://get.k3s.io | \
    K3S_URL="https://${master_ip}:6443" \
    K3S_TOKEN="$TOKEN" sh -

fi

echo "=== DONE ==="