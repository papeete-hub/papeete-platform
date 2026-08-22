output "namespace" {
  description = "Namespace the controller was installed into."
  value       = helm_release.ingress_nginx.namespace
}

output "release_name" {
  description = "Helm release name (\"ingress-nginx\") — the ingress class every actor's overlay should reference is the chart's own default, \"nginx\"."
  value       = helm_release.ingress_nginx.name
}

output "chart_version" {
  description = "Chart version actually installed (resolved by Helm when var.chart_version is null)."
  value       = helm_release.ingress_nginx.version
}
