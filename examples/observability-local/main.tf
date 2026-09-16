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

# Reachable once this name resolves to the ingress controller — see this example's README
# for the hosts-file entry. Set to null to skip the Ingress and port-forward instead.
variable "grafana_host" {
  description = "Hostname to expose Grafana on. Null creates no Ingress."
  type        = string
  default     = "grafana.local"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

module "observability" {
  source = "../../modules/observability"

  grafana_ingress_host = var.grafana_host
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

output "grafana_url" {
  value = module.observability.grafana_url
}
