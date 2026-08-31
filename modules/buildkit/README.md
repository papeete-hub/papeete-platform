# `buildkit`

Runs [BuildKit](https://github.com/moby/buildkit) as an ordinary in-cluster Deployment, so
anything in the cluster can build an OCI image and push it to a registry **without a Docker
socket**. One builder, shared by every actor and product in that cluster — nothing here names one
of them ([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)).

Built from `kubernetes_*` resources rather than a `helm_release`: BuildKit publishes an example
manifest, not a chart, and the security context below is the entire substance of the module. Why
this belongs here rather than in each actor that builds —
[ADR-PL-0002](../../adr/ADR-PL-0002-image-building-is-shared-platform-infrastructure.md).

As with every module here, the `kubernetes` provider is supplied by the caller — a root module, or
[`examples/buildkit-local`](../../examples/buildkit-local/).

## Use directly

```hcl
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

module "buildkit" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/buildkit?ref=v0.2.0"

  registry_auth = {
    server   = module.acr.login_server
    username = module.acr.push_username
    password = module.acr.push_password
  }
}
```

Then hand `module.buildkit.buildkit_addr` to whatever builds — the direct analogue of
`modules/observability`'s `otlp_grpc_endpoint`, and the only value a client needs:

```bash
BUILDKIT_HOST=tcp://buildkitd.buildkit.svc.cluster.local:1234 \
  buildctl build --frontend dockerfile.v0 --local context=. --local dockerfile=. \
    --output type=image,name=<registry>/<repo>:<tag>,push=true
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Namespace buildkitd runs in | `"buildkit"` |
| `create_namespace` | Create it, or expect it to exist | `true` |
| `name` | Deployment, Service and container name | `"buildkitd"` |
| `image` | buildkit image — must be a `-rootless` variant | `"moby/buildkit:v0.17.2-rootless"` |
| `replicas` | Replica count (each has its own cache) | `1` |
| `port` | TCP port buildkitd and its Service listen on | `1234` |
| `registry_auth` | `{ server, username, password }` for pushing; null builds without publishing | `null` |
| `docker_config_dir` | Where the credentials Secret is mounted, and `DOCKER_CONFIG` | `"/home/user/.docker"` |
| `resources` | Requests and limits as maps | `null` |

## Outputs

| Name | Description |
|---|---|
| `buildkit_addr` | `tcp://<service>.<namespace>.svc.cluster.local:<port>` — a client's `BUILDKIT_HOST` |
| `namespace` | Namespace installed into |
| `service_name` | Service name |
| `socket_addr` | The unix socket, for `buildctl --addr` inside a `kubectl exec` |

## Unprivileged, and what that costs

**No `privileged`, no `hostPath`, no `hostNetwork`, no Docker socket.** The pod runs as uid/gid
1000 and unshares its own user namespace, which needs exactly two relaxations:

- `seccompProfile: Unconfined` — set through the provider's `seccomp_profile` block.
- **AppArmor unconfined** — set through the
  `container.apparmor.security.beta.kubernetes.io/<container>` pod annotation, because the
  `kubernetes` provider (2.38) still has no `app_armor_profile` field in `security_context`. The
  annotation is deprecated in favour of that field and remains honoured; it is also what BuildKit's
  own Kubernetes example uses. Swap it when the provider catches up.

`--oci-worker-no-process-sandbox` follows from the same constraint: rootless BuildKit cannot nest
a second user namespace for the OCI worker, so the pod's own is the sandbox. A build therefore
runs with the pod's privileges — fine for a builder only cluster workloads can reach, worth
knowing before exposing it more widely.

## The cache is an `emptyDir`

It dies with the pod, and a restart means a cold rebuild. Deliberate: a build cache is a
rebuildable optimisation, and a PVC would tie this module to a storage class. Revisit if cold
builds start hurting.

## Credentials

`registry_auth` becomes a `kubernetes.io/dockerconfigjson` Secret, mounted read-only with its
`.dockerconfigjson` key **projected to `config.json`** — `buildctl` reads `$DOCKER_CONFIG/config.json`
and would not find the Secret's own key name. The credential lands in Terraform state, as any
provider-managed secret does; scope the token to the repositories it needs
([`modules/acr`](../acr/) issues exactly such a token) rather than relying on a registry-wide one.

## Verified against

Docker Desktop's Kubernetes, on its kind-based provisioner. Rootless BuildKit needs a kernel with
unprivileged user namespaces enabled — true there, and on any recent Linux node.
