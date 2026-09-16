# The consumable half of this module: one Secret per database, shaped so a pod can take it whole
# with `envFrom`, and annotated so modules/secret-reflector mirrors it into the namespaces that
# need it — including namespaces created long after this module was applied, which is the case a
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
  for_each = toset(var.databases)

  metadata {
    # Well-known name, so a product's manifest can reference it without knowing anything about how
    # the server was provisioned.
    name        = "${var.connection_secret_prefix}-${each.value}"
    namespace   = local.namespace
    labels      = merge(local.labels, { "papeete.platform/database" = each.value })
    annotations = local.reflector_annotations
  }

  data = {
    # The ADO.NET form a .NET product binds straight to configuration.
    SQLSERVER_CONNECTION_STRING = "Server=${local.host},${var.port};Database=${each.value};User Id=sa;Password=${var.sa_password};TrustServerCertificate=True;Encrypt=True"
    SQLSERVER_HOST              = local.host
    SQLSERVER_PORT              = tostring(var.port)
    SQLSERVER_DATABASE          = each.value
    SQLSERVER_USERNAME          = "sa"
    SQLSERVER_PASSWORD          = var.sa_password
  }

  # The database has to exist before something is handed a string that names it.
  depends_on = [kubernetes_job.databases]
}
