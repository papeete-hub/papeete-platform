---
id: ADR-PL-0001
title: "papeete-platform is a standalone Terraform repo for infra shared across actors and products"
status: Accepted
date: 2026-08-22
supersedes: []
references:
  - modules/ingress-nginx/main.tf
  - examples/ingress-nginx-local/main.tf
---

# ADR-PL-0001 — papeete-platform is a standalone Terraform repo for infra shared across actors and products

## Context

Two places in the ecosystem already touch infrastructure, and neither owns what this repo is for.

[`papeete-deploy`](https://github.com/papeete-hub/papeete-deploy) resolves one `papeete-product`'s
declared actors against a registry and makes that product real in one `environment` — Compose
locally, or an actor's own kustomize overlay against a k8s namespace (`ADR-PD-0002`). Its whole
model is per-product: a `product.yaml`, a namespace, a set of actors. It has no concept of
something that exists once per **cluster**, installed before any product is deployed to it and
outliving every product that comes and goes.

[`papeete-actor`'s `ADR-PA-0025`](https://github.com/papeete-hub/papeete-actor) lets an actor's own
folder carry `deploy/terraform/` — but explicitly for infra *that actor* needs (its own database,
its own queue). That convention is deliberately actor-scoped and, per its own text, "nothing in the
Papeete ecosystem executes it yet."

Neither fits an ingress controller, a shared RabbitMQ broker, or anything else meant to be stood up
**once** and used **by every actor or product in a cluster/environment**, not owned by any single
one of them. That gap is this repo.

A third, unrelated "platform" already exists in the ecosystem's vocabulary and must not be confused
with this one: `foundation/platform/adr/` is the **PCM** (Platform Capability Method) — a
methodology for designing a *domain-specific* platform (e.g. a banking platform serving one
business's product line, worked example `papeete-foundry/banking-tech`), top-down from a domain
brainstorm through strategic/tactical ADRs to PCM YAML. That's a design method for a
business-scoped platform; it is not this repo. `papeete-platform` is domain-agnostic and sits one
level down — the shared plumbing any actor needs regardless of which business it serves.

## Decision

**`papeete-platform` is a standalone repo of independently deployable Terraform modules**, one per
shared platform component, under `modules/<name>/`. Each module is a complete root module on its
own — `terraform init && terraform apply` inside it, no wrapper required — and can also be composed
from elsewhere via `source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/
<name>?ref=vX.Y.Z"`.

Not Kubernetes-exclusive: a module targets whatever provider its component needs (`kubernetes`/
`helm` for cluster addons today; a cloud provider for non-cluster resources like a managed queue or
DNS zone later). Nothing in this repo's structure assumes every future module lives inside a k8s
cluster.

The first module is [`modules/ingress-nginx`](../modules/ingress-nginx/) — installs an ingress
controller into an existing cluster via the `helm` provider. Scope for this first slice is
deliberately narrow: one module, verified only against Docker Desktop's Kubernetes (the same target
`papeete-deploy`'s own k8s path is verified against).

## Rationale

**Terraform, not Kustomize/Compose, because state matters here.** `papeete-deploy` never keeps
state of its own — a product's actors are re-resolved and re-applied idempotently every run
(`ADR-PD-0002`). Shared infra is different: an ingress controller or a broker is provisioned once,
then left alone; knowing what already exists and only changing what changed is exactly what
Terraform state is for. It's also the tool `ADR-PA-0025` already named for this kind of
longer-lived infra, so this repo continues that vocabulary rather than inventing a second one.

**A repo of independently deployable modules, not one monolithic stack.** A product's environment
may need an ingress controller without needing a message broker, or vice versa — bundling every
shared component into one `terraform apply` would force an all-or-nothing footprint on every
environment. Per-module state also means one component's drift or failure doesn't block another's.

**Provider-agnostic by design, not Kubernetes-only.** "Platform" here means whatever many actors or
products share, and not everything they share lives in a cluster (a DNS zone, a managed database, a
cloud queue). Naming this repo's structure after Kubernetes primitives (à la `papeete-actor`'s
`deploy/k8s/`) would have baked in an assumption this repo is meant to outlive.

## Consequences

- **`papeete-deploy` is untouched.** It still assumes whatever a product's environment depends on
  (an ingress class, a broker) already exists; this repo is how that dependency gets provisioned,
  not something `papeete-deploy` calls.
- **`ADR-PA-0025`'s `deploy/terraform/` is untouched.** It remains for infra one specific actor
  owns. A module here never takes an actor or product name as input — if a variable would only ever
  be set to one actor's identity, that module belongs in the actor's own folder instead, not here.
- **The PCM (`foundation/platform/adr/`) is untouched, and this repo has no dependency on it.** A
  domain-specific platform designed via PCM (a banking platform, etc.) may choose to consume a
  module here as a generic building block for its own tactical infra; nothing here reads a PCM
  artefact or assumes such a platform exists.
- **No PyPI-style release.** Modules are consumed by git ref (`?ref=vX.Y.Z`), Terraform's own
  registry-free convention — this repo tags releases (`git tag vX.Y.Z`) but publishes nothing to a
  package index.
- **Open — how an environment declares which platform modules it expects.** Nothing yet links a
  `product.yaml`'s `environment` to "this namespace needs `ingress-nginx` applied first." Today
  that's a manual/CI step run against this repo directly; making it declarative is future work, not
  solved here.
- **Open — module count stays at one (`ingress-nginx`) until a second real need shows up** (e.g.
  RabbitMQ). Adding modules speculatively ahead of a concrete consumer is explicitly out of scope
  for this ADR.
