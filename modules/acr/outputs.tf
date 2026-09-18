output "login_server" {
  description = "Registry hostname images are named against (<name>.azurecr.io) — the IMAGE_REGISTRY every builder and every image reference is composed from."
  value       = azurerm_container_registry.this.login_server
}

output "name" {
  description = "Registry name, for `az acr` commands (retention runs, tag listings)."
  value       = azurerm_container_registry.this.name
}

output "id" {
  description = "Registry resource id, for role assignments or diagnostic settings the caller owns."
  value       = azurerm_container_registry.this.id
}

output "username" {
  description = "Admin account username (the registry name). Null unless var.admin_enabled. Registry-wide and able to push — see the README before handing it to a Pod."
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_username : null
}

output "password" {
  description = "Admin account password. Null unless var.admin_enabled."
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_password : null
  sensitive   = true
}
