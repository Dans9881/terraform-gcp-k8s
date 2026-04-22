terraform {
  backend "gcs" {
    # config provided via -backend-config
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

module "network" {
  source = "../../modules/network"

  name        = "${var.vm_name}-${var.environment}-vpc"
  subnet_cidr = var.subnet_cidr
  region      = var.region
}

module "firewall" {
  source = "../../modules/firewall"

  environment = var.environment
  network     = module.network.network

  public_ports          = var.public_ports
  private_ports         = var.private_ports
  public_source_ranges  = var.public_source_ranges
  private_source_ranges = var.private_source_ranges

  target_tags = var.target_tags
}

resource "google_compute_firewall" "internal" {
  name    = "${var.vm_name}-${var.environment}-internal"
  network = module.network.network

  allow {
    protocol = "all"
  }

  source_ranges = var.internal_source_ranges
  target_tags   = var.target_tags
}

module "vm_master" {
  source = "../../modules/vm"

  name         = "${var.vm_name}-master"
  machine_type = var.master_machine_type
  disk_size    = var.master_disk_size

  zone       = var.zone
  network    = module.network.network
  subnetwork = module.network.subnet

  ssh_user    = var.ssh_user
  public_key  = file(var.public_key_path)
  private_key = file(var.private_key_path)

  tags = concat(var.target_tags, ["master"])

  repo_url           = var.repo_url
  node_role          = "master"
  tailscale_auth_key = var.tailscale_auth_key
  environment        = var.environment
}

module "vm_worker" {
  source = "../../modules/vm"

  count = var.worker_count

  name         = "${var.vm_name}-worker-${count.index}"
  machine_type = var.worker_machine_type
  disk_size    = var.worker_disk_size

  zone       = var.zone
  network    = module.network.network
  subnetwork = module.network.subnet

  ssh_user    = var.ssh_user
  public_key  = file(var.public_key_path)
  private_key = file(var.private_key_path)

  tags = concat(var.target_tags, ["worker"])

  repo_url           = var.repo_url
  node_role          = "worker"
  master_ip          = module.vm_master.internal_ip
  tailscale_auth_key = var.tailscale_auth_key
  environment        = var.environment
}