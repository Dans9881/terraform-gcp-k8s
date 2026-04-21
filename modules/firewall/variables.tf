variable "environment" {
  type = string
}

variable "network" {
  type = string
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

variable "target_tags" {
  type = list(string)
}