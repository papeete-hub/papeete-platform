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

variable "registry_server" {
  description = "Registry buildkitd pushes to, e.g. papeetefoundry.azurecr.io (the acr module's login_server). Null installs a builder that cannot publish."
  type        = string
  default     = null
}

variable "registry_username" {
  description = "Push token username (the acr module's push_username)."
  type        = string
  default     = null
}

variable "registry_password" {
  description = "Push token password (the acr module's push_password)."
  type        = string
  default     = null
  sensitive   = true
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

module "buildkit" {
  source = "../../modules/buildkit"

  registry_auth = var.registry_server == null ? null : {
    server   = var.registry_server
    username = var.registry_username
    password = var.registry_password
  }
}

output "buildkit_addr" {
  value = module.buildkit.buildkit_addr
}

output "namespace" {
  value = module.buildkit.namespace
}

output "socket_addr" {
  value = module.buildkit.socket_addr
}
