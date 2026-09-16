output "namespace" {
  description = "Namespace the server was installed into."
  value       = local.namespace
}

output "service_name" {
  description = "In-cluster Service name, for a port-forward or a same-namespace client."
  value       = kubernetes_service.this.metadata[0].name
}

output "host" {
  description = "Fully-qualified in-cluster hostname of the server."
  value       = local.host
}

output "port" {
  description = "TCP port the server listens on."
  value       = var.port
}

output "endpoint" {
  description = "host,port in the form sqlcmd and .NET connection strings expect — SQL Server separates the port with a comma, not a colon."
  value       = "${local.host},${var.port}"
}

output "databases" {
  description = "The databases this module created on the shared server, echoed back for a caller wiring products up."
  value       = var.databases
}

output "connection_strings" {
  description = "One ready-to-use ADO.NET connection string per declared database, keyed by database name. TrustServerCertificate=True because the server has only its own self-signed certificate. Sensitive: each embeds the sa credential, which is the only login this module creates."
  sensitive   = true
  value = {
    for db in var.databases :
    db => "Server=${local.host},${var.port};Database=${db};User Id=sa;Password=${var.sa_password};TrustServerCertificate=True;Encrypt=True"
  }
}

output "sa_secret_name" {
  description = "Name of the Secret holding the sa password, for a workload that would rather mount it than take the connection string."
  value       = kubernetes_secret.sa_password.metadata[0].name
}
