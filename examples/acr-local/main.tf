terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "subscription_id" {
  description = "Azure subscription the registry is created in. Leave null to take it from ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Resource group created to hold the registry."
  type        = string
  default     = "papeete-foundry-local"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "registry_name" {
  description = "Registry name — globally unique across Azure, so override this."
  type        = string
  default     = "papeetefoundry"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

module "acr" {
  source = "../../modules/acr"

  name                = var.registry_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # The two breeds of image the foundry product publishes: capability-scoped components and
  # their tests under bnk.rlvr/, product-scoped actor images under foundry/.
  repository_patterns = ["bnk.rlvr/*", "foundry/*"]
}

output "login_server" {
  value = module.acr.login_server
}

output "push_username" {
  value = module.acr.push_username
}

output "push_password" {
  value     = module.acr.push_password
  sensitive = true
}

output "pull_username" {
  value = module.acr.pull_username
}

output "pull_password" {
  value     = module.acr.pull_password
  sensitive = true
}
