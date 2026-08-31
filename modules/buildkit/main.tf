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
    "app.kubernetes.io/component"  = "image-builder"
    "app.kubernetes.io/managed-by" = "terraform"
  }

  # Rootless buildkitd listens on both: the unix socket for an `exec` into the pod, TCP for
  # every client reaching it through the Service.
  socket_addr = "unix:///run/user/1000/buildkit/buildkitd.sock"

  docker_config = var.registry_auth == null ? null : jsonencode({
    auths = {
      (var.registry_auth.server) = {
        username = var.registry_auth.username
        password = var.registry_auth.password
        auth     = base64encode("${var.registry_auth.username}:${var.registry_auth.password}")
      }
    }
  })
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_secret" "registry_auth" {
  count = var.registry_auth == null ? 0 : 1

  metadata {
    name      = "${var.name}-registry-auth"
    namespace = local.namespace
    labels    = local.labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = local.docker_config
  }
}

resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { "app.kubernetes.io/name" = var.name }
    }

    template {
      metadata {
        labels = local.labels

        # AppArmor has to be unconfined for rootless buildkit to unshare user namespaces. The
        # kubernetes provider (2.38) has no app_armor_profile field in security_context, so this
        # goes through the annotation buildkit's own Kubernetes example uses — still honoured,
        # and keyed by container name.
        annotations = {
          "container.apparmor.security.beta.kubernetes.io/${var.name}" = "unconfined"
        }
      }

      spec {
        container {
          name  = var.name
          image = var.image

          args = [
            "--addr", local.socket_addr,
            "--addr", "tcp://0.0.0.0:${var.port}",
            # Rootless buildkit cannot nest another user namespace for the OCI worker; the
            # single unshare the pod already runs in is the sandbox.
            "--oci-worker-no-process-sandbox",
          ]

          port {
            name           = "buildkit"
            container_port = var.port
          }

          dynamic "env" {
            for_each = var.registry_auth == null ? [] : [1]
            content {
              name  = "DOCKER_CONFIG"
              value = var.docker_config_dir
            }
          }

          # No privileged, no hostPath, no hostNetwork — the whole point of the rootless image.
          security_context {
            privileged   = false
            run_as_user  = 1000
            run_as_group = 1000

            seccomp_profile {
              type = "Unconfined"
            }
          }

          volume_mount {
            name       = "buildkitd"
            mount_path = "/home/user/.local/share/buildkit"
          }

          dynamic "volume_mount" {
            for_each = var.registry_auth == null ? [] : [1]
            content {
              name       = "registry-auth"
              mount_path = var.docker_config_dir
              read_only  = true
            }
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
              command = ["buildctl", "debug", "workers"]
            }
            initial_delay_seconds = 5
            period_seconds        = 30
          }

          liveness_probe {
            exec {
              command = ["buildctl", "debug", "workers"]
            }
            initial_delay_seconds = 5
            period_seconds        = 30
          }
        }

        # The build cache lives here, and dies with the pod. Deliberate: a cache is a rebuildable
        # optimisation, and a PVC would tie this module to a storage class.
        volume {
          name = "buildkitd"
          empty_dir {}
        }

        dynamic "volume" {
          for_each = var.registry_auth == null ? [] : [1]
          content {
            name = "registry-auth"
            secret {
              secret_name = kubernetes_secret.registry_auth[0].metadata[0].name
              # buildctl reads $DOCKER_CONFIG/config.json; the Secret's own key is not that name.
              items {
                key  = ".dockerconfigjson"
                path = "config.json"
              }
            }
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
      name        = "buildkit"
      port        = var.port
      target_port = var.port
    }
  }
}
