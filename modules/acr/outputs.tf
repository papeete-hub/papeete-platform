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

output "push_username" {
  description = "Username of the push token — for a builder that publishes images."
  value       = azurerm_container_registry_token.push.name
}

output "push_password" {
  description = "Password of the push token."
  value       = azurerm_container_registry_token_password.push.password1[0].value
  sensitive   = true
}

output "pull_username" {
  description = "Username of the read-only pull token — for an imagePullSecret."
  value       = azurerm_container_registry_token.pull.name
}

output "pull_password" {
  description = "Password of the pull token."
  value       = azurerm_container_registry_token_password.pull.password1[0].value
  sensitive   = true
}

output "admin_username" {
  description = "Admin account username (the registry name). Null unless var.admin_enabled — and prefer a token: this credential is registry-wide."
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_username : null
}

output "admin_password" {
  description = "Admin account password. Null unless var.admin_enabled."
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_password : null
  sensitive   = true
}
