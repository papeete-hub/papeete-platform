terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

variable "subscription_id" {
  description = "Azure subscription the registry is created in. Leave null to take it from ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Resource group created to hold the registry."
  type        = string
  default     = "papeete-foundry-local"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "registry_name" {
  description = "Registry name — globally unique across Azure, so override this."
  type        = string
  default     = "papeetefoundry"
}

variable "kube_context" {
  description = "kubectl context the pull Secret is created in."
  type        = string
  default     = "docker-desktop"
}

variable "pull_secret_namespaces" {
  description = "Namespaces to create the pull Secret in. Every namespace that runs an image from this registry needs one — a Secret is namespaced, and there is no cluster-wide form."
  type        = list(string)
  default     = ["default"]
}

variable "pull_secret_name" {
  description = "Name of the pull Secret, referenced as imagePullSecrets by anything running these images."
  type        = string
  default     = "acr-pull"
}

variable "node_registry_bypass" {
  description = "Write a containerd hosts.toml on the Docker Desktop node so pulls from this registry skip the pull-through mirror. This is what makes ACR pulls deterministic there — see the comment on terraform_data.node_registry_bypass. Set false on any cluster that isn't Docker Desktop."
  type        = bool
  default     = true
}

variable "node_container" {
  description = "Name of the Docker container running the cluster node, for var.node_registry_bypass."
  type        = string
  default     = "desktop-control-plane"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

module "acr" {
  source = "../../modules/acr"

  name                = var.registry_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # sku and admin_enabled are left at the module's defaults (Basic, admin on) on purpose: this
  # example is what ADR-PL-0006 was written against, and a registry that opts out of either one
  # here would stop being the worked example of it.
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# What a Pod authenticates with. Since ADR-PL-0006 this is the admin account — the registry has no
# read-only credential to offer on Basic — so this Secret can push as well as pull. That is the
# known cost of the tier, not an oversight; `modules/acr`'s README spells out what it means.
resource "kubernetes_secret" "pull" {
  for_each = toset(var.pull_secret_namespaces)

  metadata {
    name      = var.pull_secret_name
    namespace = each.value
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (module.acr.login_server) = {
          username = module.acr.username
          password = module.acr.password
          auth     = base64encode("${module.acr.username}:${module.acr.password}")
        }
      }
    })
  }
}

locals {
  node_hosts_toml = <<-EOT
    server = "https://${module.acr.login_server}"

    [host."https://${module.acr.login_server}"]
      capabilities = ["pull", "resolve"]
  EOT
}

resource "terraform_data" "node_registry_bypass" {
  count = var.node_registry_bypass ? 1 : 0

  triggers_replace = [module.acr.login_server, var.node_container]

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = "printf '%s' \"$HOSTS\" | docker exec -i \"$NODE\" sh -c 'mkdir -p \"$0\" && cat > \"$0/hosts.toml\"' \"/etc/containerd/certs.d/$SERVER\""

    environment = {
      NODE   = var.node_container
      SERVER = module.acr.login_server
      HOSTS  = local.node_hosts_toml
    }
  }
}

output "login_server" {
  value = module.acr.login_server
}

output "username" {
  description = "Admin account username — what a builder logs in with, and what is in the pull Secret."
  value       = module.acr.username
}

output "password" {
  description = "Admin account password. Registry-wide and able to push."
  value       = module.acr.password
  sensitive   = true
}

output "pull_secret_name" {
  description = "Name of the Secret created in each of var.pull_secret_namespaces."
  value       = var.pull_secret_name
}
