variable "databases" {
  description = "Databases to create on the shared server, one per product using it. Required with no default, the same way modules/acr's repository_patterns is: the server is shared and product-agnostic, so what lives on it is the caller's declaration. Creation is guarded by IF DB_ID(...) IS NULL, and removing a name here does NOT drop the database — see the README."
  type        = list(string)

  validation {
    condition     = length(var.databases) > 0
    error_message = "Declare at least one database — a server with no database is a server nothing can use."
  }

  validation {
    condition     = length(var.databases) == length(distinct(var.databases))
    error_message = "Database names must be unique."
  }

  validation {
    # These names are interpolated into the provisioning script, so the set of accepted characters
    # is also what keeps that interpolation from being an injection point.
    condition     = alltrue([for db in var.databases : can(regex("^[A-Za-z][A-Za-z0-9_-]{0,62}$", db))])
    error_message = "Each database name must start with a letter and contain only letters, digits, underscores or hyphens (max 63 characters)."
  }
}

variable "sa_password" {
  description = "Password for the sa login. Required with no default. Must satisfy SQL Server's own complexity policy, or the server exits on first boot with a message only visible in the pod log."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sa_password) >= 8 && length(var.sa_password) <= 128
    error_message = "SQL Server requires between 8 and 128 characters."
  }

  validation {
    condition = length([
      for pattern in ["[a-z]", "[A-Z]", "[0-9]", "[^a-zA-Z0-9]"] :
      pattern if can(regex(pattern, var.sa_password))
    ]) >= 3
    error_message = "SQL Server's complexity policy needs at least three of: lowercase, uppercase, digit, non-alphanumeric."
  }
}

variable "namespace" {
  description = "Namespace the server is installed into. Defaults to the same namespace modules/rabbitmq uses, so one shared-services namespace holds both."
  type        = string
  default     = "platform"
}

variable "create_namespace" {
  description = "Whether this module creates var.namespace, or expects it to already exist. Set false on the second module when installing both this and modules/rabbitmq into one namespace — otherwise both try to create it."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the StatefulSet, Service and container. Also the in-cluster hostname products connect to."
  type        = string
  default     = "sqlserver"
}

variable "image" {
  description = "SQL Server image. Microsoft publishes no Helm chart, which is why this module is built from kubernetes_* resources."
  type        = string
  default     = "mcr.microsoft.com/mssql/server:2025-latest"
}

variable "tools_image" {
  description = "Image supplying sqlcmd for the database-provisioning Job. Deliberately not the server image, which is ~1.5GB to pull for one query."
  type        = string
  default     = "mcr.microsoft.com/mssql-tools:latest"
}

variable "sqlcmd_path" {
  description = "Absolute path to sqlcmd inside var.tools_image. Worth a variable because the path moved between tool generations: mcr.microsoft.com/mssql-tools ships it at /opt/mssql-tools/bin/sqlcmd, while images carrying the ODBC 18 generation use /opt/mssql-tools18/bin/sqlcmd. Set this whenever tools_image is changed."
  type        = string
  default     = "/opt/mssql-tools/bin/sqlcmd"
}

variable "edition" {
  description = "MSSQL_PID — the edition the server runs as. 'Developer' is full-featured and free, but licensed for development and test only; a shared environment serving anything real needs 'Express' (free, capped) or a paid edition. Choosing this is a licensing decision, so it has no silent production default."
  type        = string
  default     = "Developer"

  validation {
    condition     = contains(["Developer", "Express", "Standard", "Enterprise", "EnterpriseCore"], var.edition)
    error_message = "Must be one of: Developer, Express, Standard, Enterprise, EnterpriseCore."
  }
}

variable "port" {
  description = "TCP port the server listens on and the Service exposes."
  type        = number
  default     = 1433
}

variable "storage_size" {
  description = "Size of the PersistentVolumeClaim backing /var/opt/mssql — system databases, every product's database, and the logs."
  type        = string
  default     = "20Gi"
}

variable "storage_class_name" {
  description = "StorageClass for the data volume. Null uses the cluster's default, which is what Docker Desktop's hostpath provisioner wants."
  type        = string
  default     = null
}

variable "wait_for_databases" {
  description = "Whether terraform apply blocks until the provisioning Job has actually created the databases. Leave true when anything in the same apply connects to them; false returns as soon as the Job is submitted."
  type        = bool
  default     = true
}

variable "provisioning_timeout" {
  description = "Terraform-side timeout for the provisioning Job, as a Go duration."
  type        = string
  default     = "10m"
}

variable "provisioning_timeout_seconds" {
  description = "How long the Job itself retries the first login before failing. Should stay below provisioning_timeout so the Job's own error surfaces instead of Terraform's, which says only that it waited."
  type        = number
  default     = 300
}

variable "extra_env" {
  description = "Additional environment variables for the server container, e.g. { MSSQL_COLLATION = \"...\", MSSQL_MEMORY_LIMIT_MB = \"2048\" }."
  type        = map(string)
  default     = {}
}

variable "resources" {
  description = "Container resource requests and limits, as plain maps (e.g. { requests = { memory = \"2Gi\" } }). Null leaves the pod unconstrained, which is right for a local cluster and wrong for a shared one. SQL Server needs at least 2GiB to start."
  type = object({
    requests = optional(map(string), {})
    limits   = optional(map(string), {})
  })
  default = null
}
