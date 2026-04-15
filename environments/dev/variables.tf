variable "project" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "vm_name" {
  description = "Base VM name"
  type        = string
}

variable "machine_type" {
  description = "VM machine type"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "danz"
}

variable "public_key_path" {
  description = "Path ke SSH public key"
  type        = string
}

variable "source_ranges" {
  type = list(string)
}

variable "allowed_ports" {
  description = "Allowed firewall ports"
  type        = list(string)
}

variable "repo_url" {
  description = "Git repository URL for Kubernetes manifests"
  type        = string
}

variable "master_machine_type" {
  type = string
}

variable "worker_machine_type" {
  type = string
}