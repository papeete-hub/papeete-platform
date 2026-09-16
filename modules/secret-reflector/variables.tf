variable "namespace" {
  description = "Namespace the reflector controller is installed into. It watches the whole cluster regardless of where it runs."
  type        = string
  default     = "secret-reflector"
}

variable "create_namespace" {
  description = "Whether Helm should create var.namespace if it doesn't already exist."
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "reflector"
}

variable "chart_version" {
  description = "reflector chart version to install (unpinned installs whatever Helm resolves as latest — pin this for anything beyond local experimentation)."
  type        = string
  default     = null
}

variable "set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "values_yaml" {
  description = "A full Helm values.yaml document (as a string) layered under any set_values overrides. Leave null to use the chart's own defaults."
  type        = string
  default     = null
}
