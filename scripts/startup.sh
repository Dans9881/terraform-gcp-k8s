#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
LOG_FILE="/var/log/startup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== START PROVISIONING ==="
echo "ENVIRONMENT: ${environment}"

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

echo "=== FIX TIME SYNC ==="
timedatectl set-ntp true || true
apt update -y || true
apt install -y systemd-timesyncd ca-certificates || true
systemctl enable systemd-timesyncd || true
systemctl restart systemd-timesyncd || true
update-ca-certificates

wait_time_sync() {
  echo "=== WAIT TIME SYNC ==="
  for i in {1..30}; do
    if timedatectl status | grep -q "System clock synchronized: yes"; then
      echo "Time synchronized OK"
      timedatectl status
      return 0
    fi
    echo "Waiting time sync ($i/30)..."
    sleep 2
  done

  echo "Time sync FAILED, forcing fallback..."
  hwclock -s || true
  date -s "$(curl -sI https://google.com | grep -i '^date:' | cut -d' ' -f3-6)" || true
}
wait_time_sync

echo "=== INSTALL DEPENDENCIES ==="
retry 5 apt update -y
retry 5 apt install -y curl git openssh-client

case "${environment}" in
  dev)
    echo "=== DEV MODE ==="
    echo "Skip Tailscale"
    ;;

  staging)
    echo "=== STAGING MODE ==="

    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable tailscaled
    systemctl start tailscaled

    tailscale up \
      --authkey ${tailscale_auth_key} \
      --hostname ${node_role}-$(hostname)

    echo "STAGING: Tailscale enabled (for testing)"
    ;;

  prod)
    echo "=== PROD MODE ==="

    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable tailscaled
    systemctl start tailscaled

    tailscale up \
      --authkey ${tailscale_auth_key} \
      --hostname ${node_role}-$(hostname)

    echo "=== VERIFY TAILSCALE CONNECTION ==="
    sleep 5
    tailscale status || { echo "Tailscale not connected!"; exit 1; }
    ;;

  *)
    echo "Unknown environment: ${environment}"
    exit 1
    ;;
esac

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

if [ "${environment}" != "dev" ]; then
  echo "=== VERIFY TAILSCALE CONNECTION ==="
  sleep 5
  tailscale status || { echo "Tailscale not connected!"; exit 1; }
fi

echo "=== MASTER NODE ==="
if [ "${node_role}" = "master" ]; then

  echo "=== INSTALL CONTAINERD ==="
  apt install -y containerd
  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd

echo "=== DISABLE SWAP ==="
swapoff -a
sed -i '/swap/d' /etc/fstab

echo "=== ADD KUBERNETES REPO ==="
mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /
EOF

apt update
apt install -y kubelet kubeadm kubectl
systemctl enable kubelet

echo "=== CREATE KUBEADM CONFIG (DISABLE KUBE-PROXY) ==="
NODE_IP=$(hostname -I | awk '{print $1}')

cat <<EOF > /etc/kubernetes/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.29.15
networking:
  podSubnet: 10.42.0.0/16

---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    node-ip: $NODE_IP

---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "none"
EOF

  echo "=== INIT CLUSTER (NO KUBE-PROXY) ==="
  kubeadm init --config /etc/kubernetes/kubeadm-config.yaml

  chmod 644 /etc/kubernetes/admin.conf

  echo "=== SETUP KUBECONFIG ==="
  mkdir -p /home/${ssh_user}/.kube
  cp /etc/kubernetes/admin.conf /home/${ssh_user}/.kube/config
  chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.kube/config
  chmod 600 /home/${ssh_user}/.kube/config

  export KUBECONFIG=/etc/kubernetes/admin.conf

  wait_resource "API READY" "kubectl get --raw='/readyz'"
  sleep 10
  wait_resource "NODE READY" "kubectl get nodes --no-headers | grep -q Ready"

  echo "=== TAINT MASTER NODE ==="
  MASTER_NODE=$(hostname)
  kubectl taint nodes $MASTER_NODE node-role.kubernetes.io/control-plane=true:NoSchedule --overwrite || true
  
  echo "=== FORCE REMOVE KUBE-PROXY (SAFETY) ==="
  kubectl -n kube-system delete daemonset kube-proxy --ignore-not-found
  kubectl -n kube-system delete configmap kube-proxy --ignore-not-found

  echo "=== INSTALL CILIUM CLI ==="
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/$${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
  tar xzvf cilium-linux-amd64.tar.gz
  mv cilium /usr/local/bin/
  rm cilium-linux-amd64.tar.gz

  echo "=== INSTALL CILIUM (CLEAN CONFIG) ==="
  cilium install \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=$(hostname -I | awk '{print $1}') \
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
  rm -rf /tmp/infra-k8s || true
  retry 5 git clone ${repo_url} /tmp/infra-k8s

  cp -r /tmp/infra-k8s/k8s/* /srv/k8s/
  cp /tmp/infra-k8s/deploy.sh /srv/k8s/
  rm -rf /tmp/infra-k8s
  cd /srv/k8s
  chmod +x deploy.sh

  echo "=== FIX PERMISSION ==="
  chown -R ${ssh_user}:${ssh_user} /srv/k8s

  sleep 15

  echo "=== RUN DEPLOY ==="
  sudo -H -u ${ssh_user} bash -c "export KUBECONFIG=/home/${ssh_user}/.kube/config && bash /srv/k8s/deploy.sh"

echo "=== WORKER NODE ==="
elif [ "${node_role}" = "worker" ]; then

  wait_resource "MASTER API" "curl -k https://${master_ip}:6443"

  echo "=== INSTALL CONTAINERD ==="
  apt install -y containerd
  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd

  echo "=== DISABLE SWAP ==="
  swapoff -a
  sed -i '/swap/d' /etc/fstab

  echo "=== ADD KUBERNETES REPO ==="
  mkdir -p /etc/apt/keyrings

  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /
EOF

  apt update
  apt install -y kubelet kubeadm
  systemctl enable kubelet

  echo "=== GET JOIN COMMAND ==="
  for i in {1..60}; do
    JOIN_CMD=$(ssh -i /home/${ssh_user}/.ssh/id_ed25519 \
      -o StrictHostKeyChecking=no \
      ${ssh_user}@${master_ip} \
      "sudo kubeadm token create --print-join-command 2>/dev/null")

    if [[ "$JOIN_CMD" == kubeadm* ]]; then
      break
    fi

    echo "Waiting join command ($i/60)..."
    sleep 5
  done

  if [ -z "$${JOIN_CMD:-}" ]; then
    echo "Failed get join command"
    exit 1
  fi

  echo "=== JOIN WORKER ==="
  $JOIN_CMD

echo "=== INSTALL NGINX (WORKER ONLY) ==="
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
        proxy_pass http://$(hostname -I | awk '{print $1}'):30080;

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
        server $(hostname -I | awk '{print $1}'):30443;
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

echo "=== INSTALL DOCKER (RUNNER) ==="
apt update
apt install -y docker.io

systemctl enable docker
systemctl start docker

usermod -aG docker ${ssh_user}

fi

echo "=== DONE (${environment}) ==="