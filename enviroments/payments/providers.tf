terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  #backend block
  backend "azurerm" {
    resource_group_name  = "ci-cd-pipeline-backend-rg"
    storage_account_name = "cicdpipestorageacc"
    container_name       = "ci-cd-container"
    key                  = "payments.tfstate"
  }
}

provider "azurerm" {
  features {}
}