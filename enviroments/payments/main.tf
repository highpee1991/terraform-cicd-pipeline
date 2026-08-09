module "infrastructure" {
  source = "../../modules/infrastructure"

  project_name                 = var.project_name
  location                     = var.location
  vm_size                      = var.vm_size
  admin_username               = var.admin_username
  address_space                = var.address_space
  subnet_prefix                = var.subnet_prefix
  environment                  = var.environment
  backend_storage_account_name = var.backend_storage_account_name
  backend_container_name       = var.backend_container_name
  backend_state_key            = var.backend_state_key
  ssh_public_key_path          = var.ssh_public_key_path
}

variable "project_name" {}
variable "location" { default = "EAST US" }
variable "vm_size" { default = "Standard_B1ls" }
variable "admin_username" {}
variable "address_space" {}
variable "subnet_prefix" {}
variable "environment" {}
variable "backend_storage_account_name" { default = "cicdpipestorageacc" }
variable "backend_container_name" { default = "ci-cd-container" }
variable "backend_state_key" {}
variable "ssh_public_key_path" {}


output "ssh_command" {
  value = module.infrastructure.ssh_command
}

output "public_ip" {
  value = module.infrastructure.public_ip
}