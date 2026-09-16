# The consumable half of this module: one Secret per vhost, shaped so a pod can take it whole with
# `envFrom`, and annotated so modules/secret-reflector mirrors it into the namespaces that need it
# — including namespaces created long after this module was applied, which is the case a
# caller-declared list of namespaces cannot serve.
#
# Without a reflector installed these Secrets are still created and still correct; they simply stay
# in this namespace, where a same-namespace pod can use them.

locals {
  reflector_annotations = var.reflect_to_namespaces == null ? {} : {
    "reflector.v1.k8s.emberstack.com/reflection-allowed"            = "true"
    "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = var.reflect_to_namespaces
    # auto-enabled is what makes a namespace created tomorrow get a copy without anything being
    # re-applied. Without it a mirror has to be requested by each consumer.
    "reflector.v1.k8s.emberstack.com/reflection-auto-enabled"    = "true"
    "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = var.reflect_to_namespaces
  }
}

resource "kubernetes_secret" "connection" {
  for_each = toset(var.vhosts)

  metadata {
    # Well-known name, so a product's manifest can reference it without knowing anything about how
    # the broker was provisioned.
    name        = "${var.connection_secret_prefix}-${each.value}"
    namespace   = local.namespace
    labels      = merge(local.labels, { "papeete.platform/vhost" = each.value })
    annotations = local.reflector_annotations
  }

  data = {
    RABBITMQ_URI      = "amqp://${var.admin_username}:${urlencode(var.admin_password)}@${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local:${var.amqp_port}/${urlencode(each.value)}"
    RABBITMQ_HOST     = "${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local"
    RABBITMQ_PORT     = tostring(var.amqp_port)
    RABBITMQ_VHOST    = each.value
    RABBITMQ_USERNAME = var.admin_username
    RABBITMQ_PASSWORD = var.admin_password
  }
}
