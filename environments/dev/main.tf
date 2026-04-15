terraform {
  backend "gcs" {
    bucket = "terraform-state-danz"
    prefix = "k3s/dev"
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

module "firewall" {
  source = "../../modules/firewall"

  name          = "${var.vm_name}-${var.environment}"
  network       = module.network.network
  ports         = var.allowed_ports
  source_ranges = var.source_ranges

  target_tags   = ["k3s"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-all"
  network = module.network.network

  allow {
    protocol = "all"
  }

  source_ranges = ["10.10.0.0/24"]

  target_tags = ["k3s"]
}

module "network" {
  source = "../../modules/network"

  name        = "${var.vm_name}-${var.environment}-vpc"
  subnet_cidr = "10.10.0.0/24"
  region      = var.region
}

module "master" {
  source = "../../modules/vm"

  name         = "${var.vm_name}-master-${var.environment}"
  machine_type = var.master_machine_type
  zone         = var.zone

  network    = module.network.network
  subnetwork = module.network.subnet

  repo_url = var.repo_url

  ssh_user   = var.ssh_user
  public_key = file(var.public_key_path)
  private_key = file("C:/Users/Danz/.ssh/id_ed25519")

  tags = ["k3s", "master"]

  node_role = "master"
}

module "worker" {
  source = "../../modules/vm"

  for_each = toset(["worker1"])
  depends_on = [module.master]

  name         = "${var.vm_name}-${each.key}-${var.environment}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  network    = module.network.network
  subnetwork = module.network.subnet

  repo_url = var.repo_url

  ssh_user   = var.ssh_user
  public_key = file(var.public_key_path)
  private_key = file("C:/Users/Danz/.ssh/id_ed25519")

  tags = ["k3s", "worker"]

  node_role  = "worker"
  master_ip  = module.master.public_ip
}