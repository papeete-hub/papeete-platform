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
platform is scoped to the business it serves. `papeete-platform` sits one level down, underneath
any of them: it doesn't know or care what domain an actor belongs to, only that actors need to be
reachable and to talk to each other. A domain-specific platform MAY consume this repo's modules as
generic building blocks for its own infra (an ingress controller is an ingress controller
regardless of the domain on top), but that's a decision made in that platform's own tech-tact
ADRs, never assumed here.

```
modules/
  ingress-nginx/     installs an ingress controller into an existing k8s cluster
examples/
  ingress-nginx-local/   the worked example, against Docker Desktop's Kubernetes
```

Each module under `modules/` is a complete, independently deployable root module — no wrapper, no
umbrella stack. Not Kubernetes-exclusive: a future module can target any provider its component
needs (a cloud DNS zone, a managed queue), not only `kubernetes`/`helm`.

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

Only [`modules/ingress-nginx`](./modules/ingress-nginx/) — an ingress controller, the one shared
piece of infra multiple actors in a cluster consistently need. Nothing else ships speculatively
ahead of a concrete need (ADR-PL-0001's Consequences).

## Boundary

- **A module here never takes an actor or product identity as input.** If a variable would only
  ever be set to one actor's name, that infra belongs in that actor's own `deploy/terraform/`
  instead (`papeete-actor`'s `ADR-PA-0025`), not here.
- **This repo provisions; `papeete-deploy` consumes.** `papeete-deploy` still assumes an
  environment's shared infra (an ingress class, a broker) already exists — it never calls into this
  repo, and this repo never reads a `product.yaml`.
- **This repo is domain-agnostic; a "banking platform" (or any other) is domain-specific.** Nothing
  here is designed via the PCM methodology or carries a `zoning` — a domain-specific platform is
  free to build on top of a module here, but this repo has no dependency in the other direction.

## Releasing

Modules are consumed by git ref, Terraform's own registry-free convention — no package index, no
publish step:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Licence

MIT.
