resource "google_compute_instance" "vm" {
  name = "${var.name}-${var.environment}"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size
      type  = var.disk_type
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {} # public IP
  }

  metadata = {
    ssh-keys   = "${var.ssh_user}:${var.public_key}"
    environment = var.environment
  }

  metadata_startup_script = templatefile("${path.module}/../../scripts/startup.sh", {
    ssh_user    = var.ssh_user
    repo_url    = var.repo_url
    node_role   = var.node_role
    master_ip   = var.master_ip
    private_key = var.private_key
    tailscale_auth_key = var.tailscale_auth_key
    environment = var.environment
  })

  tags = concat(var.tags, [var.environment])
}