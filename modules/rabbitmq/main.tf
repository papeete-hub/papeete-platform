terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : var.namespace

  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/component"  = "message-broker"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  # Where the definitions Secret is mounted. A subdirectory of /etc/rabbitmq on purpose: the
  # official image writes conf.d/10-defaults.conf into that directory at boot, so mounting
  # /etc/rabbitmq itself would shadow what the image needs to create.
  definitions_dir  = "/etc/rabbitmq/definitions"
  definitions_file = "${local.definitions_dir}/definitions.json"

  # Every vhost the caller declared, granted in full to the single admin user. Per-vhost users
  # are deliberately not generated here — see "Remains to realize" in the README.
  definitions = {
    users = [{
      name     = var.admin_username
      password = var.admin_password
      tags     = ["administrator"]
    }]

    vhosts = [for v in var.vhosts : { name = v }]

    permissions = [for v in var.vhosts : {
      user      = var.admin_username
      vhost     = v
      configure = ".*"
      write     = ".*"
      read      = ".*"
    }]

    # Present and empty rather than absent: the definitions importer rejects a document it cannot
    # match against its expected shape.
    policies          = []
    parameters        = []
    global_parameters = []
    queues            = []
    exchanges         = []
    bindings          = []
  }
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

# The broker's own config. `load_definitions` is the only line that matters: it is what turns the
# caller's `vhosts` list into vhosts that exist on boot, with no post-apply provisioning step and
# no second provider pointed at the running broker.
resource "kubernetes_config_map" "config" {
  metadata {
    name      = "${var.name}-config"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    "rabbitmq.conf" = <<-EOT
      load_definitions = ${local.definitions_file}
      ${var.extra_config}
    EOT
  }
}

# A Secret rather than a ConfigMap: this document carries the admin password in clear text, which
# is what the definitions importer accepts in place of a password hash.
resource "kubernetes_secret" "definitions" {
  metadata {
    name      = "${var.name}-definitions"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    "definitions.json" = jsonencode(local.definitions)
  }
}

resource "kubernetes_stateful_set" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    # One broker for the whole cluster, and exactly one replica. Clustering RabbitMQ needs peer
    # discovery and a shared Erlang cookie, which is the point at which the cluster operator earns
    # its CRDs — see the README's rejected alternatives.
    replicas     = 1
    service_name = kubernetes_service.headless.metadata[0].name

    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }

    template {
      metadata {
        labels = local.labels

        # Roll the pod when either document changes: the definitions are read at boot, so a new
        # vhost in the list is otherwise invisible until something else restarts the broker.
        annotations = {
          "papeete.platform/config-hash"      = sha1(jsonencode(kubernetes_config_map.config.data))
          "papeete.platform/definitions-hash" = sha1(jsonencode(local.definitions))
        }
      }

      spec {
        security_context {
          # The official image runs as uid 999; fs_group is what makes the PVC writable by it.
          run_as_user  = 999
          run_as_group = 999
          fs_group     = 999
        }

        container {
          name  = var.name
          image = var.image

          port {
            name           = "amqp"
            container_port = var.amqp_port
          }

          port {
            name           = "management"
            container_port = var.management_port
          }

          env {
            name  = "RABBITMQ_CONFIG_FILE"
            value = "/etc/rabbitmq/rabbitmq.conf"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/rabbitmq/rabbitmq.conf"
            sub_path   = "rabbitmq.conf"
            read_only  = true
          }

          volume_mount {
            name       = "definitions"
            mount_path = local.definitions_dir
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/rabbitmq"
          }

          dynamic "resources" {
            for_each = var.resources == null ? [] : [var.resources]
            content {
              requests = resources.value.requests
              limits   = resources.value.limits
            }
          }

          readiness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "-q", "check_port_connectivity"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 10
          }

          liveness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "-q", "status"]
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 15
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config.metadata[0].name
          }
        }

        volume {
          name = "definitions"
          secret {
            secret_name = kubernetes_secret.definitions.metadata[0].name
          }
        }
      }
    }

    # Mnesia's directory is keyed by node name, and the node name is the pod's hostname — which is
    # why this is a StatefulSet. A Deployment would hand the broker a new name on every roll and
    # orphan the data it had just written.
    volume_claim_template {
      metadata {
        name   = "data"
        labels = local.labels
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class_name

        resources {
          requests = {
            storage = var.storage_size
          }
        }
      }
    }
  }
}

# Stable per-pod DNS, which is what keeps the Erlang node name constant across a roll.
resource "kubernetes_service" "headless" {
  metadata {
    name      = "${var.name}-headless"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type       = "ClusterIP"
    cluster_ip = "None"
    selector   = { "app.kubernetes.io/name" = var.name }

    port {
      name        = "amqp"
      port        = var.amqp_port
      target_port = "amqp"
    }
  }
}

# What every product connects to.
resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type     = "ClusterIP"
    selector = { "app.kubernetes.io/name" = var.name }

    port {
      name        = "amqp"
      port        = var.amqp_port
      target_port = "amqp"
    }

    port {
      name        = "management"
      port        = var.management_port
      target_port = "management"
    }
  }
}
