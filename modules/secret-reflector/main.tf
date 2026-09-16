terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

resource "helm_release" "reflector" {
  name             = var.release_name
  repository       = "https://emberstack.github.io/helm-charts"
  chart            = "reflector"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.values_yaml == null ? null : [var.values_yaml]

  dynamic "set" {
    for_each = var.set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}
