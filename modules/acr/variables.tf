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

variable "sku" {
  description = "Registry SKU. Basic by default — it is the whole cost of this module, and the tiers above it buy included storage, geo-replication and repository-scoped tokens that ADR-PL-0006 records this registry does not use. Raise it only for a reason that ADR names."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be one of Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = "Whether the registry's single admin account is enabled. On by default: since ADR-PL-0006 it is the only credential this module issues, so turning it off leaves the registry with no way in short of an Entra role assignment the caller makes itself."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Azure resource tags applied to the registry."
  type        = map(string)
  default     = {}
}
