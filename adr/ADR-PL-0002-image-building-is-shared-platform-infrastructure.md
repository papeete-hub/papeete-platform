---
id: ADR-PL-0002
title: "Image building is shared platform infrastructure: in-cluster rootless BuildKit pushing to a cloud registry"
status: Accepted
date: 2026-08-31
supersedes: []
references:
  - modules/buildkit/main.tf
  - modules/acr/main.tf
  - examples/buildkit-local/main.tf
  - examples/acr-local/main.tf
---

# ADR-PL-0002 — Image building is shared platform infrastructure

## Context

Some actors build container images as part of doing their work — a code-writing actor builds what
it wrote; a testing actor builds the test image it then runs. Until now that meant Docker
outside-of-Docker: the actor's pod mounted the node's `/var/run/docker.sock` by `hostPath` and
shelled out to `docker build`.

That mount is not available on every node, and where it is missing the consequence was severe out
of all proportion to the need: the affected actors were pulled out of Kubernetes entirely and run
as bare host processes, reachable on fixed host ports. Namespace isolation went with them, and so
did convention-derived Service names — which is what makes standing the same product up N times
(per-PR, per-branch) possible at all. A product that needs a host port cannot be stood up twice.

The need itself is narrow. The entire Docker surface of those actors is
`docker build -f <dockerfile> -t <tag> <context>` — no `run`, no `push`, no `compose`. **Building
is one function, not a property of the actor**, and a function several actors in a cluster need
identically is the definition of what this repo provisions (ADR-PL-0001).

Two things are needed for that function to leave the node: something that builds without a Docker
daemon, and somewhere to put what it builds — an actor and the ephemeral namespace that runs its
output are different pods, so the image has to travel through a registry.

## Decision

**Two modules, both shared, both installed once per environment:**

- [`modules/buildkit`](../modules/buildkit/) — rootless BuildKit as a Deployment plus a Service on
  1234, exporting `buildkit_addr`. Any workload in the cluster sets `BUILDKIT_HOST` to it and
  builds. **No `privileged`, no `hostPath`, no `hostNetwork`, no Docker socket.**
- [`modules/acr`](../modules/acr/) — an Azure Container Registry with two scope-mapped tokens, one
  push and one read-only pull, both confined to repository paths the caller declares.

Both are built from `kubernetes_*` / `azurerm_*` provider resources rather than a `helm_release`,
the first in this repo to be so. Neither has a chart worth installing: BuildKit ships an example
manifest, and a registry is a cloud resource. ADR-PL-0001 anticipated the second half of this —
*"a module targets whatever provider its component needs … a cloud provider for non-cluster
resources"* — and this is that case arriving.

**Neither module names an actor or a product.** `modules/acr`'s `repository_patterns` is a required
input with no default, so the paths a token may reach are the caller's declaration; the examples
supply them.

## Rationale

**A cloud registry rather than one inside the cluster.** An in-cluster registry was built and
proven working — 55ms pulls — and rejected. Docker Desktop routes every registry pull through a
pull-through mirror declared in the node's `certs.d/_default`, which swallows an in-cluster
address; making it work needed a pinned ClusterIP, `hostAliases`, and a privileged DaemonSet
writing a node file that does not survive a cluster recreate. All of it Docker-Desktop-specific,
none of it transferable, and the privileged DaemonSet would have reintroduced exactly the node
coupling this decision exists to remove. External registries, by contrast, pass through the mirror
cleanly with **no node configuration at all** — measured against quay.io, public.ecr.aws and
ghcr.io before committing to this. That is the load-bearing fact: ACR needs no `hosts.toml`, no
DaemonSet, and therefore no privileged component anywhere.

**Rootless, not privileged.** A privileged builder is a node-level escape hatch handed to whatever
can reach it. The rootless image needs only `seccompProfile: Unconfined`, AppArmor unconfined and
`--oci-worker-no-process-sandbox`, all of which stay inside the pod. A build still runs with the
builder pod's own privileges — acceptable for a builder only cluster workloads can reach, and
recorded here rather than left implicit.

**Scope-mapped tokens rather than a service principal.** A token is registry-local, scoped to a
path prefix, rotated by replacing one resource, and consumed as a plain `dockerconfigjson` Secret.
A service principal would carry a directory identity and registry-wide RBAC to do the same job.

**The alternative was widening a product contract to say "this actor is not a pod."** Rejected: it
would have made the workaround permanent and expressible, when the workaround is what was wrong.
Removing the need for a bare host process is the fix.

## Consequences

- **`papeete-deploy` and `papeete-product` are untouched by this ADR.** As with every module here,
  this repo provisions and they consume; nothing in either calls into this repo.
- **A departure recorded on purpose:** two modules that are not `helm_release`. The per-resource
  `chart_version` / `set_values` / `values_yaml` shape described in `CLAUDE.md` applies to Helm
  modules and does not generalise; each new module's README states which it is.
- **Build cache is an `emptyDir`** and dies with the builder pod. A PVC would tie the module to a
  storage class; revisit if cold rebuilds start to hurt.
- **Registry latency is now on the inner loop.** Local pulls were 55ms; a cloud registry is a WAN
  round-trip each way, on every build/test iteration. Worth measuring once real component images
  are moving.
- **Inherited, not widened — ADR-PL-0001's open item.** Nothing links a `product.yaml`'s
  `environment` to "this cluster needs `buildkit` and a registry applied first." These two modules
  inherit that gap exactly as `ingress-nginx` does.
- **Docker Desktop needs one `hosts.toml` per registry, and only Docker Desktop does.** Its node
  routes every registry through `kind-registry-mirror`, which cannot serve a private registry: it
  has no credential store of its own, and it forwards the ACR bearer token across ACR's blob
  redirect to Azure Storage, which rejects it — the node then reports a short read and does not
  fall back. One per-registry `hosts.toml` takes the registry out of the mirror's path (measured:
  deterministic 11–13s pulls, versus indefinite `ImagePullBackOff` without). It names a stable
  public hostname rather than a ClusterIP, needs no `hostAliases` and no privileged DaemonSet, so
  it is a documented local prerequisite `examples/acr-local` applies — not the node coupling this
  ADR rejected. Clusters without that mirror need nothing.
- **The registry's admin account stays disabled.** It looked necessary while the mirror was still
  in the path; with the bypass, a least-privilege pull token is sufficient.
- **AppArmor is set by annotation, not by field**, because the `kubernetes` provider still has no
  `app_armor_profile` in `security_context`. The annotation is deprecated in favour of that field
  and remains honoured; swap it when the provider catches up.
