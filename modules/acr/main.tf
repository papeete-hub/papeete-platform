terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  # Scope-map actions are per repository pattern, so the caller's list is crossed with the
  # verbs each token needs. Push implies read: a layer already present is mounted, not re-sent.
  push_actions = flatten([
    for pattern in var.repository_patterns : [
      "repositories/${pattern}/content/read",
      "repositories/${pattern}/content/write",
      "repositories/${pattern}/metadata/read",
      "repositories/${pattern}/metadata/write",
    ]
  ])

  pull_actions = flatten([
    for pattern in var.repository_patterns : [
      "repositories/${pattern}/content/read",
      "repositories/${pattern}/metadata/read",
    ]
  ])
}

resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = var.admin_enabled
  tags                = var.tags
}

resource "azurerm_container_registry_scope_map" "push" {
  name                    = "${var.name}-push"
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name
  description             = "Build and publish images under ${join(", ", var.repository_patterns)}."
  actions                 = local.push_actions
}

resource "azurerm_container_registry_scope_map" "pull" {
  name                    = "${var.name}-pull"
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name
  description             = "Read-only pull of images under ${join(", ", var.repository_patterns)}."
  actions                 = local.pull_actions
}

resource "azurerm_container_registry_token" "push" {
  name                    = "${var.name}-push"
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name
  scope_map_id            = azurerm_container_registry_scope_map.push.id
  enabled                 = true
}

resource "azurerm_container_registry_token" "pull" {
  name                    = "${var.name}-pull"
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name
  scope_map_id            = azurerm_container_registry_scope_map.pull.id
  enabled                 = true
}

resource "azurerm_container_registry_token_password" "push" {
  container_registry_token_id = azurerm_container_registry_token.push.id

  password1 {
    expiry = var.token_password_expiry
  }
}

resource "azurerm_container_registry_token_password" "pull" {
  container_registry_token_id = azurerm_container_registry_token.pull.id

  password1 {
    expiry = var.token_password_expiry
  }
}
