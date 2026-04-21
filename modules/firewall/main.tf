resource "google_compute_firewall" "public" {
  name    = "${var.environment}-public"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = var.public_ports
  }

  source_ranges = var.public_source_ranges
  target_tags   = var.target_tags
}

resource "google_compute_firewall" "private" {
  name    = "${var.environment}-private"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = var.private_ports
  }

  source_ranges = var.private_source_ranges
  target_tags   = var.target_tags
}