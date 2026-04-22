variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "vm_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "danz"
}

variable "public_key_path" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "repo_url" {
  type = string
}

variable "master_machine_type" {
  type = string
}

variable "worker_machine_type" {
  type = string
}

variable "master_disk_size" {
  type = number
}

variable "worker_disk_size" {
  type = number
}

variable "worker_count" {
  type    = number
  default = 1
}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

variable "public_ports" {
  type = list(string)
}

variable "private_ports" {
  type = list(string)
}

variable "public_source_ranges" {
  type = list(string)
}

variable "private_source_ranges" {
  type = list(string)
}

variable "subnet_cidr" {
  type = string
}

variable "internal_source_ranges" {
  type = list(string)
}

variable "target_tags" {
  type = list(string)
}

variable "zone_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}