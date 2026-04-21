# 🚀 Terraform Kubernetes Infrastructure (GCP)

Production-grade Kubernetes cluster on Google Cloud using Terraform with fully automated provisioning.

---

## ✨ Features

- Modular Terraform (VM, Network, Firewall)
- Multi-node Kubernetes cluster (control-plane + workers)
- Automated provisioning via kubeadm (startup scripts)
- Traefik Ingress + HTTPS (Let's Encrypt)
- Cilium CNI (kube-proxy replacement)
- Cloudflare DNS integration
- Fault-tolerant (node failure tested)
- Multi-environment support (`dev`, `staging`, `prod`)

---

## 🏗 Architecture

GCP VM (Control Plane + Workers)  
↓  
Kubernetes Cluster (kubeadm)  
↓  
Cilium (CNI)  
↓  
Traefik (Ingress Controller)  
↓  
Cloudflare DNS + HTTPS  

---

## 🔗 Related Repository

Kubernetes manifests & app deployment:  
👉 https://github.com/Dans9881/infra-k3s

---

## ⚙️ Requirements

- Terraform >= 1.0  
- Google Cloud account  
- `gcloud` CLI  
- `gsutil`  
- SSH key (`~/.ssh/id_ed25519.pub`)  

---

## ⚡ Quick Start

```bash
# Clone repo
git clone https://github.com/Dans9881/terraform-k8s
cd terraform-k8s

# Auth GCP
gcloud auth application-default login

# Create backend bucket (one-time)
gsutil mb -p <PROJECT_ID> gs://danz-tf-state

# (Optional) set custom bucket
export TF_BUCKET=danz-tf-state

# Init environment
bash scripts/init.sh dev

# Edit variables
nano environments/dev/terraform.tfvars

# Deploy 🚀
cd environments/dev
terraform plan
terraform apply