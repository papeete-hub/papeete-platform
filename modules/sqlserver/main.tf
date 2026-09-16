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
    "app.kubernetes.io/component"  = "database"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  host = "${var.name}.${local.namespace}.svc.cluster.local"

  # One CREATE per declared database, each guarded so re-running the Job is a no-op. The Job is
  # named after a hash of this script, so changing the list is what causes it to run again.
  create_databases_sql = join("\n", [
    for db in var.databases :
    "IF DB_ID(N'${db}') IS NULL BEGIN CREATE DATABASE [${db}]; PRINT 'created ${db}'; END ELSE PRINT 'exists ${db}';"
  ])
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_secret" "sa_password" {
  metadata {
    name      = "${var.name}-sa"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    # The key the server's own entrypoint reads. The provisioning Job below reads the same Secret,
    # so the credential exists in exactly one place.
    "MSSQL_SA_PASSWORD" = var.sa_password
  }
}

resource "kubernetes_stateful_set" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    # One server for every product, per this repo's rule that a database is a shared component and
    # a product gets a database on it, not a server of its own.
    replicas     = 1
    service_name = var.name

    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        security_context {
          # The image's own non-root user. fs_group is what makes the PVC writable by it — without
          # it the server exits on startup unable to create its system databases.
          run_as_user  = 10001
          run_as_group = 10001
          fs_group     = 10001
        }

        container {
          name  = var.name
          image = var.image

          port {
            name           = "mssql"
            container_port = var.port
          }

          # Accepting the EULA is a precondition of the image starting at all; it is recorded here
          # rather than hidden in a values file so that accepting it is a visible act.
          env {
            name  = "ACCEPT_EULA"
            value = "Y"
          }

          env {
            name  = "MSSQL_PID"
            value = var.edition
          }

          env {
            name = "MSSQL_SA_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.sa_password.metadata[0].name
                key  = "MSSQL_SA_PASSWORD"
              }
            }
          }

          dynamic "env" {
            for_each = var.extra_env
            content {
              name  = env.key
              value = env.value
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/opt/mssql"
          }

          dynamic "resources" {
            for_each = var.resources == null ? [] : [var.resources]
            content {
              requests = resources.value.requests
              limits   = resources.value.limits
            }
          }

          readiness_probe {
            tcp_socket {
              port = var.port
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = var.port
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
        }
      }
    }

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
      name        = "mssql"
      port        = var.port
      target_port = "mssql"
    }
  }
}

# SQL Server has no equivalent of the definitions file RabbitMQ imports at boot, and its image runs
# no init scripts, so creating the caller's databases takes an actual connection. A Job is the
# cheapest thing that can hold one: it needs no second Terraform provider pointed at the server,
# and therefore no provider that would have to be configurable before the server it talks to
# exists.
resource "kubernetes_job" "databases" {
  metadata {
    # The hash is what makes this re-run: a Job's template is immutable, so adding a database has
    # to produce a differently-named Job rather than an update to this one.
    name      = "${var.name}-databases-${substr(sha1(local.create_databases_sql), 0, 8)}"
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    backoff_limit = 4

    template {
      metadata {
        labels = local.labels
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "create-databases"
          image = var.tools_image

          env {
            name = "SA_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.sa_password.metadata[0].name
                key  = "MSSQL_SA_PASSWORD"
              }
            }
          }

          # A readiness probe reports the port is open well before the server will accept a login,
          # so the Job waits on a query succeeding rather than on the Service. -C trusts the
          # server's self-signed certificate, which is the only kind it has here.
          command = ["/bin/bash", "-c", <<-EOT
            set -euo pipefail
            for i in $(seq 1 ${var.provisioning_timeout_seconds / 5}); do
              if ${var.sqlcmd_path} -S ${local.host},${var.port} -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1; then
                echo "server accepted a login after $((i * 5))s"
                exec ${var.sqlcmd_path} -S ${local.host},${var.port} -U sa -P "$SA_PASSWORD" -C -b -Q "${replace(local.create_databases_sql, "\"", "\\\"")}"
              fi
              sleep 5
            done
            echo "server did not accept a login within ${var.provisioning_timeout_seconds}s" >&2
            exit 1
          EOT
          ]
        }
      }
    }
  }

  # Without this the Job is created and Terraform returns before any database exists, so a caller
  # that wires a product up in the same apply races it.
  wait_for_completion = var.wait_for_databases

  timeouts {
    create = var.provisioning_timeout
    update = var.provisioning_timeout
  }

  depends_on = [kubernetes_stateful_set.this, kubernetes_service.this]
}
