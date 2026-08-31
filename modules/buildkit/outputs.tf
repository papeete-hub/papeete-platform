output "buildkit_addr" {
  description = "Address a client sets BUILDKIT_HOST to — the one value anything building an image in this cluster needs."
  value       = "tcp://${kubernetes_service.this.metadata[0].name}.${local.namespace}.svc.cluster.local:${var.port}"
}

output "namespace" {
  description = "Namespace buildkitd was installed into."
  value       = local.namespace
}

output "service_name" {
  description = "In-cluster Service name, for a port-forward or a same-namespace client."
  value       = kubernetes_service.this.metadata[0].name
}

output "socket_addr" {
  description = "The unix socket buildkitd also listens on, for `kubectl exec` into the pod (buildctl --addr)."
  value       = local.socket_addr
}
