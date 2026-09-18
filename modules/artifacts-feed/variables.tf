variable "organization_name" {
  description = "Azure DevOps organization the feed is created in — the leading path segment of both dev.azure.com/<org> and pkgs.dev.azure.com/<org>. The caller owns the organization: it is not an ARM resource, no provider can create one, and this module never tries. One variable rather than a name and a URL, because every host this module touches derives from it and two inputs for one fact are two ways to disagree."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,62}[A-Za-z0-9]$", var.organization_name))
    error_message = "Organization name must be 2-64 characters of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "name" {
  description = "Feed name, and the segment packages are addressed under (.../_packaging/<name>/pypi/simple/). It also prefixes the two Entra applications this module creates, as <name>-publish and <name>-consume."
  type        = string
  default     = "papeete-python"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$", var.name)) && !endswith(var.name, ".")
    error_message = "Feed name must be at most 64 characters of letters, digits, dots, underscores and hyphens, must start with a letter or digit, and must not end with a dot."
  }
}

variable "upstream_sources" {
  description = "Package sources the feed proxies, as Azure Artifacts upstream sources. The PyPI default is the premise of this module rather than a convenience: the feed is meant to REPLACE pypi.org as the single index, not to sit beside it — an index that only holds the organization's own packages would have to be configured as an extra index, and an extra index is what makes dependency confusion possible. An empty list turns upstreams off entirely."
  type = list(object({
    name                 = string
    protocol             = string
    location             = string
    upstream_source_type = optional(string, "public")
  }))
  default = [{
    name     = "PyPI"
    protocol = "pypi"
    location = "https://pypi.org/"
  }]

  validation {
    condition     = alltrue([for source in var.upstream_sources : contains(["public", "internal"], source.upstream_source_type)])
    error_message = "Each upstream source type must be either public or internal."
  }
}

variable "configure_upstream_sources" {
  description = "Whether to apply the upstream configuration through az rest. The azuredevops provider's feed schema is name, project and two delete flags — it cannot express an upstream at all — so this one setting is a local-exec against the REST API. Set it to false where az is unavailable or unauthenticated, and configure the upstreams by hand; the feed and both identities are provisioned either way."
  type        = bool
  default     = true
}

variable "publisher_subject_patterns" {
  description = "Subjects allowed to PUBLISH, as GitHub OIDC sub patterns where * is a wildcard (e.g. [\"repo:papeete-hub/*:environment:release\"]). No default on purpose: a feed shared by every repository in an organization should say which of them may write to it. These are whole subjects rather than repository names because that is what the credential matches — a repository and the environment or ref its run carries — and because the expression language has no or operator, so each pattern is its own credential."
  type        = list(string)

  validation {
    condition     = length(var.publisher_subject_patterns) > 0
    error_message = "At least one publisher subject pattern is required — an identity that matches nothing can publish nothing."
  }

  validation {
    condition     = length(var.publisher_subject_patterns) <= 20
    error_message = "At most 20 publisher subject patterns are allowed — Entra caps federated identity credentials at 20 per application, and each pattern is one credential."
  }

  validation {
    condition     = alltrue([for pattern in var.publisher_subject_patterns : startswith(pattern, "repo:")])
    error_message = "Each publisher subject pattern must start with \"repo:\" — that is the shape of every subject GitHub Actions issues."
  }
}

variable "consumer_subject_patterns" {
  description = "Subjects allowed to RESOLVE from the feed and to save third-party packages from its upstreams. Deliberately separate from publisher_subject_patterns and normally much broader: every branch and every pull request has to resolve dependencies, while only a release may publish. The consuming identity cannot write a package of its own, so breadth here costs far less than breadth there."
  type        = list(string)

  validation {
    condition     = length(var.consumer_subject_patterns) > 0
    error_message = "At least one consumer subject pattern is required — an identity that matches nothing can resolve nothing."
  }

  validation {
    condition     = length(var.consumer_subject_patterns) <= 20
    error_message = "At most 20 consumer subject patterns are allowed — Entra caps federated identity credentials at 20 per application, and each pattern is one credential."
  }

  validation {
    condition     = alltrue([for pattern in var.consumer_subject_patterns : startswith(pattern, "repo:")])
    error_message = "Each consumer subject pattern must start with \"repo:\" — that is the shape of every subject GitHub Actions issues."
  }
}

variable "github_repository_owner_id" {
  description = "Numeric id of the GitHub organization the workflows belong to, read from `gh api orgs/<org> --jq .id`. Required because Entra rejects a claims expression that matches sub alone: a GitHub expression must also pin repository_id or repository_owner_id. The numeric id is the point — it is immutable, so a pattern cannot be satisfied by someone who registers the organization's name after it is given up."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "The repository owner id must be digits only — it is GitHub's numeric id for the organization, not its name."
  }
}

variable "oidc_issuer" {
  description = "Issuer of the tokens the credentials trust. Defaults to GitHub Actions; flexible federated identity credentials only accept GitHub, GitLab and Terraform Cloud issuers, and the claims this module writes are GitHub's."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "oidc_audience" {
  description = "Audience the incoming token must carry. api://AzureADTokenExchange is what azure/login sends and what Entra expects — change it only alongside the workflow that requests the token."
  type        = string
  default     = "api://AzureADTokenExchange"
}

variable "retention_count_limit" {
  description = "Maximum number of versions kept per package. Retention matters more here than on a registry that only holds what you built: with an upstream, every third-party wheel anyone resolves is cached and counts against the organization's storage, and deleted packages keep counting for 30 days."
  type        = number
  default     = 50

  validation {
    condition     = var.retention_count_limit > 0
    error_message = "The count limit must be at least 1 — a feed that keeps no version of anything is a feed nothing can resolve."
  }
}

variable "retention_days_to_keep_recently_downloaded_packages" {
  description = "Days a package version is kept after it was last downloaded, regardless of the count limit. This is what stops retention from deleting an old version something still pins."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days_to_keep_recently_downloaded_packages > 0
    error_message = "The number of days to keep recently downloaded packages must be at least 1."
  }
}

variable "account_license_type" {
  description = "Azure DevOps license granted to both service principals. It must be express (shown as Basic in the web interface): a stakeholder license does not reach a feed at all. Each identity consumes one of the five free Basic licenses, and this module takes two of them."
  type        = string
  default     = "express"

  validation {
    condition     = contains(["advanced", "earlyAdopter", "express", "basic", "professional"], var.account_license_type)
    error_message = "The account license type must be one of advanced, earlyAdopter, express, basic or professional — stakeholder and none cannot reach a feed."
  }
}

variable "azure_devops_resource_id" {
  description = "Entra application id of Azure DevOps, used as the --resource of the az rest call that configures the upstreams. It is the same well-known constant in every tenant; it is a variable so that the constant is declared in one place and named, rather than appearing unexplained inside a shell command."
  type        = string
  default     = "499b84ac-1321-427f-aa17-267ca6975798"
}
