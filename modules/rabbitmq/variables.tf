variable "vhosts" {
  description = "Virtual hosts to create, one per product sharing this broker. Required with no default, the same way modules/acr's repository_patterns is: the broker is shared and product-agnostic, so what lives on it is the caller's declaration, not this module's. Note that removing a name here does NOT delete the vhost from a broker that already has it — see the README."
  type        = list(string)

  validation {
    condition     = length(var.vhosts) > 0
    error_message = "Declare at least one vhost — a broker with no vhost but / is a broker nothing can use without sharing one namespace."
  }

  validation {
    condition     = length(var.vhosts) == length(distinct(var.vhosts))
    error_message = "Vhost names must be unique."
  }
}

variable "namespace" {
  description = "Namespace the broker is installed into. Defaults to the same namespace modules/sqlserver uses, so one shared-services namespace holds both."
  type        = string
  default     = "platform"
}

variable "create_namespace" {
  description = "Whether this module creates var.namespace, or expects it to already exist. Set false on the second module when installing both this and modules/sqlserver into one namespace — otherwise both try to create it."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the StatefulSet, Services and container. Also the in-cluster hostname products connect to."
  type        = string
  default     = "rabbitmq"
}

variable "image" {
  description = "RabbitMQ image. The -management variants ship the management plugin and its HTTP API, which is what makes the broker inspectable without an exec."
  type        = string
  default     = "rabbitmq:4-management"
}

variable "admin_username" {
  description = "Administrator user created from the imported definitions, with full permissions on every declared vhost."
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Administrator password. Required with no default: a shared broker with a default password is a shared broker with no password. Written into the definitions Secret in clear text, which is what the definitions importer takes in place of a hash."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "Use at least 8 characters."
  }
}

variable "amqp_port" {
  description = "AMQP port the broker listens on and the Service exposes."
  type        = number
  default     = 5672
}

variable "management_port" {
  description = "Management UI / HTTP API port."
  type        = number
  default     = 15672
}

variable "storage_size" {
  description = "Size of the PersistentVolumeClaim backing /var/lib/rabbitmq. Queue data and the definitions the broker has imported live here."
  type        = string
  default     = "8Gi"
}

variable "storage_class_name" {
  description = "StorageClass for the data volume. Null uses the cluster's default, which is what Docker Desktop's hostpath provisioner wants."
  type        = string
  default     = null
}

variable "extra_config" {
  description = "Additional rabbitmq.conf lines, appended verbatim below this module's load_definitions line. For settings the broker reads from its own config file rather than from definitions."
  type        = string
  default     = ""
}

variable "resources" {
  description = "Container resource requests and limits, as plain maps (e.g. { requests = { cpu = \"500m\" } }). Null leaves the pod unconstrained, which is right for a local cluster and wrong for a shared one."
  type = object({
    requests = optional(map(string), {})
    limits   = optional(map(string), {})
  })
  default = null
}

variable "connection_secret_prefix" {
  description = "Name prefix for the per-vhost connection Secrets — the well-known name a product's manifest references. A vhost named 'reliever' yields 'platform-rabbitmq-reliever' by default."
  type        = string
  default     = "platform-rabbitmq"
}

variable "reflect_to_namespaces" {
  description = "Regex (or comma-separated regexes) of namespaces the connection Secrets are mirrored into by modules/secret-reflector, matched against namespaces that exist now AND ones created later. Null, the default, annotates nothing: the Secrets stay in this namespace and only a same-namespace pod can use them. Requires modules/secret-reflector to be installed in the cluster — the annotations are inert without it."
  type        = string
  default     = null
}
