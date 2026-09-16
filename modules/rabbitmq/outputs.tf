output "namespace" {
  description = "Namespace the broker was installed into."
  value       = local.namespace
}

output "service_name" {
  description = "In-cluster Service name, for a port-forward or a same-namespace client."
  value       = kubernetes_service.this.metadata[0].name
}

output "host" {
  description = "Fully-qualified in-cluster hostname of the broker."
  value       = "${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local"
}

output "amqp_port" {
  description = "AMQP port."
  value       = var.amqp_port
}

output "amqp_endpoint" {
  description = "host:port an AMQP client connects to. Carries no vhost — see amqp_uris for one URI per declared vhost."
  value       = "${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local:${var.amqp_port}"
}

output "amqp_uris" {
  description = "One ready-to-use amqp:// URI per declared vhost, keyed by vhost name — what a product sets its connection string to. Sensitive: each embeds the admin credential, which is the only credential this module creates."
  sensitive   = true
  value = {
    for v in var.vhosts :
    v => "amqp://${var.admin_username}:${urlencode(var.admin_password)}@${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local:${var.amqp_port}/${urlencode(v)}"
  }
}

output "vhosts" {
  description = "The vhosts this module declared to the broker, echoed back for a caller wiring products up."
  value       = var.vhosts
}

output "management_url" {
  description = "In-cluster URL of the management UI and HTTP API. Reach it locally with: kubectl -n <namespace> port-forward svc/<service_name> <management_port>."
  value       = "http://${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local:${var.management_port}"
}

output "connection_secret_names" {
  description = "Name of the connection Secret for each vhost, keyed by vhost — what a pod puts in envFrom.secretRef. Not sensitive: these are names, not credentials."
  value       = { for v in var.vhosts : v => kubernetes_secret.connection[v].metadata[0].name }
}
