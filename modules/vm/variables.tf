variable "name" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "zone" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "public_key" {
  type = string
}

variable "private_key" {
  type = string
}

variable "tags" {
  type = list(string)
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "disk_size" {
  type    = number
  default = 50
}

variable "disk_type" {
  type    = string
  default = "pd-standard"
}

variable "image" {
  type    = string
  default = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "repo_url" {
  type = string
}

variable "node_role" {
  type = string
}

variable "master_ip" {
  type    = string
  default = ""
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key"
  type        = string
  sensitive   = true
}

variable "environment" {
  type = string
}