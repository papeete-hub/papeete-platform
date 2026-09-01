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
  description = "Namespaces to create the read-only pull Secret in. Every namespace that runs an image from this registry needs one — a Secret is namespaced, and there is no cluster-wide form."
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

  # The two breeds of image the foundry product publishes: capability-scoped components and
  # their tests under bnk.rlvr/, product-scoped actor images under foundry/.
  repository_patterns = ["bnk.rlvr/*", "foundry/*"]
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# What a Pod authenticates with: the read-only token, never the admin account. This is the
# credential that matters on a real cluster, where the kubelet pulls for itself.
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
          username = module.acr.pull_username
          password = module.acr.pull_password
          auth     = base64encode("${module.acr.pull_username}:${module.acr.pull_password}")
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

output "push_username" {
  value = module.acr.push_username
}

output "push_password" {
  value     = module.acr.push_password
  sensitive = true
}

output "pull_username" {
  value = module.acr.pull_username
}

output "pull_password" {
  value     = module.acr.pull_password
  sensitive = true
}

output "pull_secret_name" {
  description = "Name of the Secret created in each of var.pull_secret_namespaces."
  value       = var.pull_secret_name
}
