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
