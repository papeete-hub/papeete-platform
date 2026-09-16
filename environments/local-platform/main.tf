terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

# The shared services every product on this cluster uses, applied once and meant to stay — unlike
# examples/*-local, which demonstrate one module each and are disposable (ADR-PL-0003).
#
# This is a root module for an ENVIRONMENT, not an umbrella module under modules/: it owns its own
# state, supplies its own providers, and exists to be applied rather than to be sourced. Nothing
# under modules/ depends on it.

variable "kube_context" {
  description = "kubectl context this environment lives in."
  type        = string
  default     = "docker-desktop"
}

variable "namespace" {
  description = "Namespace holding the shared services."
  type        = string
  default     = "platform"
}

variable "tenants" {
  description = "One name per product sharing this platform. Each gets a vhost on the broker and a database on the server — a tenant on a shared component, never a component of its own. Adding a name here is the whole act of onboarding a product."
  type        = list(string)
  default     = ["foundry", "reliever"]
}

variable "consumer_namespaces" {
  description = "Regex matching the namespaces a product is deployed into, which is where the connection Secrets are mirrored. The default matches everything, which is right for a local cluster where every namespace is yours and per-PR namespaces appear without warning; a shared environment should narrow it."
  type        = string
  default     = ".*"
}

variable "rabbitmq_admin_password" {
  description = "Broker administrator password. Defaulted only because this environment targets a local cluster."
  type        = string
  default     = "rabbitmq-local-dev"
  sensitive   = true
}

variable "sa_password" {
  description = "SQL Server sa password. Defaulted only because this environment targets a local cluster."
  type        = string
  default     = "Sqlserver-local-dev1!"
  sensitive   = true
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

# Installed first, and in its own namespace: it watches the whole cluster, and a product namespace
# created tomorrow is exactly the case it exists to serve.
module "secret_reflector" {
  source = "../../modules/secret-reflector"
}

module "rabbitmq" {
  source = "../../modules/rabbitmq"

  namespace = var.namespace
  vhosts    = var.tenants

  admin_password        = var.rabbitmq_admin_password
  reflect_to_namespaces = var.consumer_namespaces

  storage_size = "1Gi"

  # Creates the shared namespace; sqlserver below joins it.
  create_namespace = true

  depends_on = [module.secret_reflector]
}

module "sqlserver" {
  source = "../../modules/sqlserver"

  namespace = var.namespace
  databases = var.tenants

  sa_password           = var.sa_password
  reflect_to_namespaces = var.consumer_namespaces

  storage_size = "5Gi"

  # SQL Server refuses to start below 2GiB.
  resources = {
    requests = { memory = "2Gi" }
  }

  # rabbitmq already made it — two modules, one namespace, exactly one creator.
  create_namespace = false

  depends_on = [module.rabbitmq, module.secret_reflector]
}

output "namespace" {
  value = var.namespace
}

output "tenants" {
  value = var.tenants
}

output "rabbitmq_endpoint" {
  value = module.rabbitmq.amqp_endpoint
}

output "sqlserver_endpoint" {
  value = module.sqlserver.endpoint
}

output "connection_secrets" {
  description = "What a product's pod references. Both Secrets are mirrored into every namespace matching var.consumer_namespaces, so a pod uses them by name with no knowledge of this environment."
  value = {
    for t in var.tenants : t => {
      rabbitmq  = module.rabbitmq.connection_secret_names[t]
      sqlserver = module.sqlserver.connection_secret_names[t]
    }
  }
}
