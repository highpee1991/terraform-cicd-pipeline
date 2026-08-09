output "public_ip" {
  description = "public ip"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_name" {
  description = "virtual machine name"
  value       = azurerm_linux_virtual_machine.main.name
}

output "resource_group_name" {
  description = "resource group name"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "storage account name"
  value       = var.backend_storage_account_name
}

output "terraform_state_location" {
  description = "terraform state location"
  value       = "${var.backend_container_name}/${var.backend_state_key}"
}

output "ssh_command" {
  description = "SSH command to connect"
  value = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}