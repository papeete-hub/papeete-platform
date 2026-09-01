variable "name" {
  description = "Registry name — globally unique, 5-50 alphanumeric characters, and the leading label of its login server (<name>.azurecr.io)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "Registry name must be 5-50 alphanumeric characters, with no hyphens or dots."
  }
}

variable "resource_group_name" {
  description = "Resource group the registry is created in. The caller owns it — this module never creates one."
  type        = string
}

variable "location" {
  description = "Azure region the registry is created in (e.g. \"westeurope\")."
  type        = string
}

variable "repository_patterns" {
  description = "Repository paths the two tokens are scoped to, as ACR scope-map patterns (e.g. [\"bnk.rlvr/*\", \"foundry/*\"]). A trailing /* matches everything below that path. No default on purpose: a registry shared by several products should say what each token may reach."
  type        = list(string)

  validation {
    condition     = length(var.repository_patterns) > 0
    error_message = "At least one repository pattern is required — an unscoped token defeats the point of scope maps."
  }
}

variable "sku" {
  description = "Registry SKU. Scope maps and tokens are a Premium-only feature, so anything else fails at apply."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be one of Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = "Whether the registry's single admin account is enabled. Off by default: scope-mapped tokens are the credential this module exists to issue. Turn it on only where something needs a registry-wide credential — Docker Desktop's pull-through mirror is the known case, and examples/acr-local explains why."
  type        = bool
  default     = false
}

variable "token_password_expiry" {
  description = "RFC3339 expiry for both token passwords (e.g. \"2027-01-01T00:00:00Z\"). Null issues non-expiring passwords."
  type        = string
  default     = null
}

variable "tags" {
  description = "Azure resource tags applied to the registry."
  type        = map(string)
  default     = {}
}
