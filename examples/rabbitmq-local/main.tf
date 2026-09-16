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

variable "admin_password" {
  description = "Broker administrator password. Defaulted here only because this example targets a throwaway local cluster; a shared environment passes its own."
  type        = string
  default     = "rabbitmq-local-dev"
  sensitive   = true
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

module "rabbitmq" {
  source = "../../modules/rabbitmq"

  # One vhost per product sharing the broker. The module never names a product itself — these are
  # the caller's declaration, exactly as modules/acr's repository_patterns are.
  vhosts = ["foundry", "reliever"]

  admin_password = var.admin_password

  # Its own namespace so this example and examples/sqlserver-local can both be applied to one
  # cluster — they are separate root modules with separate state, so both creating the module
  # default ("platform") would collide. Installing both into ONE shared namespace is the real
  # deployment shape, and the module README shows it: the second module takes create_namespace =
  # false.
  namespace = "rabbitmq-local"

  # Docker Desktop's hostpath provisioner is the default StorageClass, so storage_class_name stays
  # null and a modest claim is plenty for a local broker.
  storage_size = "1Gi"
}

output "namespace" {
  value = module.rabbitmq.namespace
}

output "amqp_endpoint" {
  value = module.rabbitmq.amqp_endpoint
}

output "vhosts" {
  value = module.rabbitmq.vhosts
}

output "management_url" {
  value = module.rabbitmq.management_url
}

output "amqp_uris" {
  value     = module.rabbitmq.amqp_uris
  sensitive = true
}
