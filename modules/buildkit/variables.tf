variable "namespace" {
  description = "Namespace buildkitd is installed into."
  type        = string
  default     = "buildkit"
}

variable "create_namespace" {
  description = "Whether this module creates var.namespace, or expects it to already exist."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the Deployment, Service and container. Also the key of the AppArmor annotation, which is keyed by container name."
  type        = string
  default     = "buildkitd"
}

variable "image" {
  description = "buildkit image. Must be a -rootless variant: the security context here runs as uid 1000 with no privileges, which the standard image cannot do."
  type        = string
  default     = "moby/buildkit:v0.17.2-rootless"

  validation {
    condition     = can(regex("rootless", var.image))
    error_message = "Image must be a rootless buildkit variant — this module never grants privileged."
  }
}

variable "replicas" {
  description = "Number of buildkitd replicas. Each has its own cache, so more than one trades cache hits for parallelism."
  type        = number
  default     = 1
}

variable "port" {
  description = "TCP port buildkitd listens on, and the Service port clients reach it through."
  type        = number
  default     = 1234
}

variable "registry_auth" {
  description = "Credentials for what the DAEMON does on its own account, written into a kubernetes.io/dockerconfigjson Secret and mounted at $DOCKER_CONFIG/config.json. This is NOT what authorizes a remote buildctl client's push — that client resolves registry auth itself and hands it over the session, so it needs its own $DOCKER_CONFIG. See the module README."
  type = object({
    server   = string
    username = string
    password = string
  })
  default   = null
  sensitive = true
}

variable "docker_config_dir" {
  description = "Directory the registry Secret is mounted at, and the value of DOCKER_CONFIG. Must be writable-adjacent to uid 1000's home in the rootless image."
  type        = string
  default     = "/home/user/.docker"
}

variable "resources" {
  description = "Container resource requests and limits, as plain maps (e.g. { requests = { cpu = \"500m\" } }). Null leaves the pod unconstrained, which is right for a local cluster and wrong for a shared one."
  type = object({
    requests = optional(map(string), {})
    limits   = optional(map(string), {})
  })
  default = null
}
