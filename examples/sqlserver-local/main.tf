terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

variable "kube_context" {
  description = "kubectl context to install into."
  type        = string
  default     = "docker-desktop"
}

variable "sa_password" {
  description = "sa password. Defaulted here only because this example targets a throwaway local cluster; a shared environment passes its own."
  type        = string
  default     = "Sqlserver-local-dev1!"
  sensitive   = true
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

module "sqlserver" {
  source = "../../modules/sqlserver"

  # One database per product sharing the server. The module never names a product itself — these
  # are the caller's declaration, never the module's.
  databases = ["foundry", "reliever"]

  sa_password = var.sa_password

  # Its own namespace so this example and examples/rabbitmq-local can both be applied to one
  # cluster — see the note in that example. The shared-namespace shape is in the module README.
  namespace = "sqlserver-local"

  # Developer edition: full-featured, free, and licensed for development and test only — which is
  # exactly what a -local example is.
  edition = "Developer"

  storage_size = "5Gi"

  # SQL Server refuses to start below 2GiB, so the floor is stated rather than discovered.
  resources = {
    requests = {
      memory = "2Gi"
    }
  }
}

output "namespace" {
  value = module.sqlserver.namespace
}

output "endpoint" {
  value = module.sqlserver.endpoint
}

output "databases" {
  value = module.sqlserver.databases
}

output "connection_strings" {
  value     = module.sqlserver.connection_strings
  sensitive = true
}
