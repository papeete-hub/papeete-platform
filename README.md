# papeete-platform

The **top-level, domain-agnostic factory**: Terraform modules for infrastructure **shared across
actors and products** — installed once per cluster/environment, owned by no single one of them,
and indifferent to which business domain the actors on top of it serve. Split out on purpose:
neither [`papeete-deploy`](https://github.com/papeete-hub/papeete-deploy) (deploys one product's
declared actors into an environment that's assumed to already have what it needs) nor
[`papeete-actor`'s `deploy/terraform/`](https://github.com/papeete-hub/papeete-actor) (an
individual actor's own infra) is the right owner for something like a cluster's ingress controller
or a broker every actor talks to. See
[ADR-PL-0001](./adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md).

**Not the same "platform" as the PCM methodology's.** `foundation/platform/adr/` (the PCM — Platform
Capability Method) is how a *domain-specific* platform gets designed — e.g. a "banking platform"
serving one business's product line, worked example `papeete-foundry/banking-tech`, built
top-down: domain → strategic platform capabilities → tactical tech ADRs → PCM YAML. That kind of
platform is scoped to the business it serves. `papeete-platform` is orthogonal to it, not
underneath it: it doesn't know or care what domain an actor belongs to, only that actors need to
be reachable and to talk to each other. **There is no link between the two** — no dependency,
consumption, or composition in either direction. A domain-specific platform's own tech-tact ADRs
choose and provision its infra entirely on their own terms.

```
modules/
  ingress-nginx/     installs an ingress controller into an existing k8s cluster
  observability/     OTel Collector, Tempo, Loki, Prometheus, Grafana — one telemetry pipeline
  buildkit/          rootless in-cluster image building, no Docker socket anywhere
  acr/               an Azure Container Registry with scope-mapped push and pull tokens
examples/
  <name>-local/      the worked example for each, against Docker Desktop's Kubernetes
```

Each module under `modules/` is a complete, independently deployable root module — no wrapper, no
umbrella stack. Not Kubernetes-exclusive: `acr` targets `azurerm`, because a registry is not a
cluster resource. A module targets whatever provider its component needs.

## Use a module

```hcl
module "ingress" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/ingress-nginx?ref=v0.1.0"
}
```

Or apply it directly — see [`examples/ingress-nginx-local`](./examples/ingress-nginx-local/):

```bash
cd examples/ingress-nginx-local
terraform init
terraform apply
```

## What's here today

Four modules, each added against a concrete need rather than speculatively (ADR-PL-0001's
Consequences):

- [`modules/ingress-nginx`](./modules/ingress-nginx/) — an ingress controller, the one shared piece
  of infra multiple actors in a cluster consistently need.
- [`modules/observability`](./modules/observability/) — one telemetry pipeline every actor exports
  to: OTel Collector on 4317 fanning out to Tempo, Loki and Prometheus, with Grafana pre-wired and
  auto-discovering the dashboards products ship in their own namespaces.
- [`modules/buildkit`](./modules/buildkit/) — rootless BuildKit as an ordinary Deployment, so an
  actor that needs to build an image no longer needs the node's Docker socket
  ([ADR-PL-0002](./adr/ADR-PL-0002-image-building-is-shared-platform-infrastructure.md)).
- [`modules/acr`](./modules/acr/) — where what it builds goes, with a push token for the builder
  and a read-only token for everything that runs the result.

The last two are built from `kubernetes_*` / `azurerm_*` resources rather than a `helm_release` —
neither has a chart worth installing. Each module's README says which it is.

## Boundary

- **A module here never takes an actor or product identity as input.** If a variable would only
  ever be set to one actor's name, that infra belongs in that actor's own `deploy/terraform/`
  instead (`papeete-actor`'s `ADR-PA-0025`), not here.
- **This repo provisions; `papeete-deploy` consumes.** `papeete-deploy` still assumes an
  environment's shared infra (an ingress class, a broker) already exists — it never calls into this
  repo, and this repo never reads a `product.yaml`.
- **This repo is orthogonal to any domain-specific platform** (a "banking platform" or any other,
  PCM-designed). Nothing here is designed via the PCM methodology or carries a `zoning`, and there
  is no dependency between the two in either direction — they simply don't relate.

## Releasing

Modules are consumed by git ref, Terraform's own registry-free convention — no package index, no
publish step:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Licence

MIT.
