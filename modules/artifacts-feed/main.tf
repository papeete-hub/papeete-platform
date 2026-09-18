terraform {
  required_version = ">= 1.5"

  required_providers {
    azuread = {
      source = "hashicorp/azuread"
      # 3.7.0 is where azuread_application_flexible_federated_identity_credential appeared.
      version = "~> 3.7"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.16"
    }
  }
}

data "azuread_client_config" "current" {}

locals {
  # Artifacts is served from feeds.dev.azure.com, not from the organization's own host — the
  # packaging endpoints do not exist under dev.azure.com, and a PATCH there returns 404.
  feed_url = "https://feeds.dev.azure.com/${var.organization_name}/_apis/packaging/feeds/${azuredevops_feed.this.id}?api-version=7.1"

  pypi_base = "https://pkgs.dev.azure.com/${var.organization_name}/_packaging/${azuredevops_feed.this.name}/pypi"

  # Everything the provider's schema cannot express. Safe to PATCH out of band: azuredevops_feed
  # sends the name alone on create and an empty object on update, so a later apply never clobbers
  # these fields — which is what makes the hybrid stable rather than a fight.
  feed_update = jsonencode({
    upstreamEnabled = length(var.upstream_sources) > 0
    upstreamSources = [for source in var.upstream_sources : {
      name               = source.name
      protocol           = source.protocol
      location           = source.location
      upstreamSourceType = source.upstream_source_type
    }]
  })

  # A federated credential's display name is immutable and must be unique on its application, so it
  # is derived from the pattern rather than from the pattern's position in the list — reordering the
  # list then moves nothing.
  publisher_credentials = { for pattern in var.publisher_subject_patterns : trim(replace(pattern, "/[^A-Za-z0-9]+/", "-"), "-") => pattern }
  #
  # Consumers can come from more than one GitHub organization, each pinned to ITS OWN owner id. The
  # home organization's patterns keep the keys they always had, so adding another organization
  # creates credentials and replaces none.
  consumer_credentials = merge(
    { for pattern in var.consumer_subject_patterns :
    trim(replace(pattern, "/[^A-Za-z0-9]+/", "-"), "-") => { pattern = pattern, owner_id = var.github_repository_owner_id } },
    { for c in var.additional_consumer_organizations :
    trim(replace(c.subject_pattern, "/[^A-Za-z0-9]+/", "-"), "-") => { pattern = c.subject_pattern, owner_id = c.owner_id } },
  )
}

resource "azuredevops_feed" "this" {
  name = var.name
}

resource "terraform_data" "upstream_sources" {
  count = var.configure_upstream_sources ? 1 : 0

  triggers_replace = [azuredevops_feed.this.id, local.feed_update]

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = "az rest --method patch --url \"$URL\" --resource \"$RESOURCE\" --headers Content-Type=application/json --body \"$BODY\""

    environment = {
      URL      = local.feed_url
      RESOURCE = var.azure_devops_resource_id
      BODY     = local.feed_update
    }
  }
}

resource "azuredevops_feed_retention_policy" "this" {
  feed_id                                   = azuredevops_feed.this.id
  count_limit                               = var.retention_count_limit
  days_to_keep_recently_downloaded_packages = var.retention_days_to_keep_recently_downloaded_packages
}

resource "azuread_application_registration" "publish" {
  display_name = "${var.name}-publish"
  description  = "Publishes Python distributions to the ${azuredevops_feed.this.name} feed from GitHub Actions."
}

resource "azuread_application_registration" "consume" {
  display_name = "${var.name}-consume"
  description  = "Resolves Python distributions from the ${azuredevops_feed.this.name} feed, and saves third-party ones from its upstreams."
}

resource "azuread_service_principal" "publish" {
  client_id = azuread_application_registration.publish.client_id
}

resource "azuread_service_principal" "consume" {
  client_id = azuread_application_registration.consume.client_id
}

resource "azuread_application_flexible_federated_identity_credential" "publish" {
  for_each = local.publisher_credentials

  application_id = azuread_application_registration.publish.id
  display_name   = each.key
  description    = "Publishes to ${azuredevops_feed.this.name} from ${each.value}."
  issuer         = var.oidc_issuer
  audience       = var.oidc_audience

  # Entra rejects an expression that matches sub alone, so every expression also pins an immutable
  # claim. repository_owner_id survives a repository being renamed or transferred within the org,
  # which a name-based sub does not.
  claims_matching_expression = "claims['sub'] matches '${each.value}' and claims['repository_owner_id'] eq '${var.github_repository_owner_id}'"
}

resource "azuread_application_flexible_federated_identity_credential" "consume" {
  for_each = local.consumer_credentials

  application_id             = azuread_application_registration.consume.id
  display_name               = each.key
  description                = "Resolves from ${azuredevops_feed.this.name} for ${each.value.pattern}."
  issuer                     = var.oidc_issuer
  audience                   = var.oidc_audience
  claims_matching_expression = "claims['sub'] matches '${each.value.pattern}' and claims['repository_owner_id'] eq '${each.value.owner_id}'"
}

resource "azuredevops_service_principal_entitlement" "publish" {
  # The object id of the SERVICE PRINCIPAL, never the application registration's: Azure DevOps
  # resolves the identity through its directory object, and an application's object id matches none.
  origin_id            = azuread_service_principal.publish.object_id
  account_license_type = var.account_license_type
}

resource "azuredevops_service_principal_entitlement" "consume" {
  origin_id            = azuread_service_principal.consume.object_id
  account_license_type = var.account_license_type
}

resource "azuredevops_feed_permission" "publish" {
  feed_id             = azuredevops_feed.this.id
  identity_descriptor = azuredevops_service_principal_entitlement.publish.descriptor
  role                = "contributor"
}

resource "azuredevops_feed_permission" "consume" {
  feed_id             = azuredevops_feed.this.id
  identity_descriptor = azuredevops_service_principal_entitlement.consume.descriptor

  # collaborator, not reader: only collaborator and above may save a package from an upstream. A
  # reader fails on the first cache miss, which is every third-party dependency on day one.
  role = "collaborator"
}
