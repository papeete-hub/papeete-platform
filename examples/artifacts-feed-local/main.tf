terraform {
  required_version = ">= 1.5"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.7"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.16"
    }
  }
}

variable "organization_name" {
  description = "Azure DevOps organization the feed is created in. It already exists — no provider can create one."
  type        = string
  default     = "papeete-consulting"
}

variable "personal_access_token" {
  description = "Azure DevOps PAT for the azuredevops provider, scoped to Packaging (read/write/manage) and Identity (read). Leave null to take it from AZDO_PERSONAL_ACCESS_TOKEN. The provider cannot authenticate from an az login, so this is the one long-lived secret the design does not remove — keep it short-lived and on the operator's machine, never in a GitHub secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "feed_name" {
  description = "Feed name. It is also the name packages are addressed under, so changing it invalidates every configured index."
  type        = string
  default     = "papeete-python"
}

variable "github_organization" {
  description = "GitHub organization whose workflows reach the feed."
  type        = string
  default     = "papeete-hub"
}

variable "github_repository_owner_id" {
  description = "Numeric id of var.github_organization, from `gh api orgs/papeete-hub --jq .id`."
  type        = string
  default     = "301756401"
}

variable "consumer_organizations" {
  description = "Other GitHub organizations that RESOLVE from the feed and never publish to it. papeete-foundry holds the capability repositories: their actor images pip-install kpack and kontract, and their CI installs papeete-version and papeete-actor, none of which exists on PyPI any more. Owner ids from `gh api orgs/<org> --jq .id`."
  type = list(object({
    owner_id        = string
    subject_pattern = string
  }))
  default = [
    { owner_id = "301756381", subject_pattern = "repo:papeete-foundry*" },
  ]
}

variable "github_environment" {
  description = "GitHub environment a run must pass through before it may publish. It is this environment's tag protection rule — not the federated credential — that restricts publishing to v* tags, because an environment-scoped subject carries no ref."
  type        = string
  default     = "azure-artifacts"
}

provider "azuread" {}

provider "azuredevops" {
  org_service_url       = "https://dev.azure.com/${var.organization_name}"
  personal_access_token = var.personal_access_token
}

module "artifacts_feed" {
  source = "../../modules/artifacts-feed"

  organization_name          = var.organization_name
  name                       = var.feed_name
  github_repository_owner_id = var.github_repository_owner_id

  # Narrow on the way in, broad on the way out. Publishing demands a run that went through the
  # azure-artifacts environment, whose tag protection rule is what confines it to a release; every
  # branch and every pull request in the organization may resolve, because every one of them has to
  # install dependencies before it can do anything at all — and the resolving identity cannot write.
  #
  # The `*` after the organization name is not decoration. GitHub issues this organization's tokens
  # in the immutable subject format, which inlines numeric ids —
  # `repo:papeete-hub@301756401/papeete-version@1341540313:environment:azure-artifacts`, not
  # `repo:papeete-hub/papeete-version:environment:azure-artifacts`. The wildcard matches either
  # form, so the credential survives GitHub switching between them, and it costs nothing: the
  # expression also pins repository_owner_id, which is what actually confines these to this
  # organization.
  publisher_subject_patterns = ["repo:${var.github_organization}*:environment:${var.github_environment}"]
  consumer_subject_patterns  = ["repo:${var.github_organization}*"]

  # Resolve-only, from other organizations. The same wildcard reasoning applies, and each is pinned
  # to its own owner id, so `repo:papeete-foundry*` cannot be met by a repository elsewhere.
  additional_consumer_organizations = var.consumer_organizations
}

output "index_url" {
  value = module.artifacts_feed.index_url
}

output "publish_url" {
  value = module.artifacts_feed.publish_url
}

output "feed_id" {
  value = module.artifacts_feed.feed_id
}

output "publish_client_id" {
  value = module.artifacts_feed.publish_client_id
}

output "consume_client_id" {
  value = module.artifacts_feed.consume_client_id
}

output "tenant_id" {
  value = module.artifacts_feed.tenant_id
}

output "github_organization_variables" {
  description = "The three GitHub organization variables every repository inherits, ready for `gh variable set`."
  value = {
    AZURE_ARTIFACTS_PUBLISH_CLIENT_ID = module.artifacts_feed.publish_client_id
    AZURE_ARTIFACTS_CONSUME_CLIENT_ID = module.artifacts_feed.consume_client_id
    AZURE_TENANT_ID                   = module.artifacts_feed.tenant_id
  }
}
