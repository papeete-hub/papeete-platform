variable "namespace" {
  description = "Namespace the ingress controller is installed into."
  type        = string
  default     = "ingress-nginx"
}

variable "create_namespace" {
  description = "Whether Helm should create var.namespace if it doesn't already exist."
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "ingress-nginx chart version to install (unpinned installs whatever Helm resolves as latest — pin this for anything beyond local experimentation)."
  type        = string
  default     = null
}

variable "set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs (e.g. { \"controller.service.type\" = \"NodePort\" })."
  type        = map(string)
  default     = {}
}

variable "values_yaml" {
  description = "A full Helm values.yaml document (as a string) layered under any set_values overrides. Leave null to use the chart's own defaults."
  type        = string
  default     = null
}
