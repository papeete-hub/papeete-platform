output "index_url" {
  description = "The single index uv and pip resolve against — set it as the default index, never as an extra one, or PyPI is back in the resolution path and so is dependency confusion."
  value       = "${local.pypi_base}/simple/"
}

output "publish_url" {
  description = "Where distributions are uploaded — uv publish's publish-url, twine's TWINE_REPOSITORY_URL."
  value       = "${local.pypi_base}/upload/"
}

output "feed_id" {
  description = "Feed GUID, for `az rest` calls against the packaging API that name a feed."
  value       = azuredevops_feed.this.id
}

output "feed_name" {
  description = "Feed name, as it appears in the organization's Artifacts view."
  value       = azuredevops_feed.this.name
}

output "publish_client_id" {
  description = "Client id of the publishing identity — the AZURE_ARTIFACTS_PUBLISH_CLIENT_ID GitHub organization variable. Not a secret, and not sensitive: it names an identity that only a token federated from a matching workflow can ever assume."
  value       = azuread_application_registration.publish.client_id
}

output "consume_client_id" {
  description = "Client id of the resolving identity — the AZURE_ARTIFACTS_CONSUME_CLIENT_ID GitHub organization variable."
  value       = azuread_application_registration.consume.client_id
}

output "publish_service_principal_object_id" {
  description = "Object id of the publishing service principal, which is how it appears under Organization settings → Users."
  value       = azuread_service_principal.publish.object_id
}

output "consume_service_principal_object_id" {
  description = "Object id of the resolving service principal."
  value       = azuread_service_principal.consume.object_id
}

output "tenant_id" {
  description = "Entra tenant both identities live in — the AZURE_TENANT_ID GitHub organization variable."
  value       = data.azuread_client_config.current.tenant_id
}

output "azure_devops_resource_id" {
  description = "Entra application id of Azure DevOps — the --resource of `az account get-access-token`, which is how a workflow turns its Entra login into a feed password. Emitted so that nobody has to go looking for it."
  value       = var.azure_devops_resource_id
}
