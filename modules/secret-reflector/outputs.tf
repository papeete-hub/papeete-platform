output "namespace" {
  description = "Namespace the reflector controller was installed into."
  value       = helm_release.reflector.namespace
}

output "release_name" {
  description = "Helm release name, for a kubectl logs when a mirror does not appear."
  value       = helm_release.reflector.name
}

output "annotation_prefix" {
  description = "Annotation prefix the controller watches. A module that wants a Secret mirrored writes <prefix>/reflection-allowed, /reflection-allowed-namespaces, /reflection-auto-enabled and /reflection-auto-namespaces — this output exists so the convention is stated in one place rather than retyped."
  value       = "reflector.v1.k8s.emberstack.com"
}
