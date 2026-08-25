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

module "observability" {
  source = "../../modules/observability"
}

output "namespace" {
  value = module.observability.namespace
}

output "otlp_grpc_endpoint" {
  value = module.observability.otlp_grpc_endpoint
}

output "grafana_service_name" {
  value = module.observability.grafana_service_name
}
