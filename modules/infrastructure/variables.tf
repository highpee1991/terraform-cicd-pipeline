variable "project_name" {
  description = "project name"
  type        = string
}

variable "location" {
  description = "project location"
  type        = string
}

variable "vm_size" {
  description = "virtual machime size"
  type        = string
}

variable "admin_username" {
  description = "admin user name"
  type        = string
}

variable "ssh_public_key" {
  description = "Path to SSH public key"
  type        = string
}

variable "address_space" {
  description = "vnet address"
  type        = string
}

variable "subnet_prefix" {
  description = "subnet address"
  type        = string
}

variable "environment" {
  description = "team"
  type        = string
}

variable "backend_storage_account_name" {
  type = string
}

variable "backend_container_name" {
  type = string
}

variable "backend_state_key" {
  type = string
}