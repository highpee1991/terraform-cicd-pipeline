locals {
  name_prefix = "${var.project_name}-${var.environment}"
  tags = {
    Project    = var.project_name
    Environment = var.environment
    Owner      = var.admin_username
    ManagedBy  = "Terraform"
  }
}




#resourse group
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location

  tags = local.tags
}

# vnet
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.address_space]

  tags = local.tags
}

# subnet
resource "azurerm_subnet" "main" {
  name                 = "${local.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefix]
}

# public ip
resource "azurerm_public_ip" "main" {
  name                = "${local.name_prefix}-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"

  tags = local.tags
}

# NSG 
resource "azurerm_network_security_group" "main" {
  name                = "${local.name_prefix}-NSG"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.tags
}

#NSG rule port 80
resource "azurerm_network_security_rule" "http" {
  name                         = "rule-port-80"
  priority                     = 100
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "80"
  source_address_prefix        = "*"
  destination_address_prefix = "*"
  resource_group_name          = azurerm_resource_group.main.name
  network_security_group_name  = azurerm_network_security_group.main.name
}

#NSG rule port 22
resource "azurerm_network_security_rule" "ssh" {
  name                         = "rule-port-22"
  priority                     = 101
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "22"
  source_address_prefix        = "*"
  destination_address_prefix = "*"
  resource_group_name          = azurerm_resource_group.main.name
  network_security_group_name  = azurerm_network_security_group.main.name
}


#Network interface card and attach public ip created
resource "azurerm_network_interface" "main" {
  name                = "${local.name_prefix}-NIC"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id #attach our public ip
  }
}

#associate nsg rule with nic
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}


resource "azurerm_linux_virtual_machine" "main" {
  name                = "${local.name_prefix}-VM"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}