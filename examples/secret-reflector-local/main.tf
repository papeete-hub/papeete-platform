terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

variable "kube_context" {
  description = "kubectl context to install into."
  type        = string
  default     = "docker-desktop"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

# The controller on its own. It does nothing visible until some Secret elsewhere carries the
# reflection annotations — see environments/local-platform, which installs this alongside the
# modules whose Secrets it mirrors.
module "secret_reflector" {
  source = "../../modules/secret-reflector"
}

output "namespace" {
  value = module.secret_reflector.namespace
}

output "annotation_prefix" {
  value = module.secret_reflector.annotation_prefix
}
