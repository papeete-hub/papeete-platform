output "namespace" {
  description = "Namespace every observability component was installed into."
  value       = var.namespace
}

output "otlp_grpc_endpoint" {
  description = "OTLP gRPC endpoint every actor's OTEL_EXPORTER_OTLP_ENDPOINT should point at — traces, logs, and metrics all fan out from here. Null when var.enable_otel_collector is false."
  value       = var.enable_otel_collector ? "otel-collector.${var.namespace}.svc.cluster.local:4317" : null
}

output "grafana_service_name" {
  description = "In-cluster service name for Grafana, for port-forwarding or an Ingress target. Null when var.enable_grafana is false."
  value       = var.enable_grafana ? "${helm_release.grafana[0].name}.${var.namespace}.svc.cluster.local" : null
}

output "grafana_url" {
  description = "URL Grafana answers on through the ingress controller. Null when no Ingress was asked for (var.grafana_ingress_host unset) or Grafana is disabled — port-forward is the only way in then. Resolving this hostname is the caller's job: nothing here writes DNS or a hosts file."
  value       = var.enable_grafana && var.grafana_ingress_host != null ? "http://${var.grafana_ingress_host}" : null
}
