---
id: ADR-PL-0004
title: "A shared component publishes a connection Secret, and reflection carries it into product namespaces"
status: Accepted
date: 2026-09-16
supersedes: []
references:
  - modules/secret-reflector/main.tf
  - modules/rabbitmq/connection_secrets.tf
  - modules/sqlserver/connection_secrets.tf
  - environments/local-platform/main.tf
---

# ADR-PL-0004 — Platform credentials reach products by reflection

## Context

A shared component is only usable if a product can find it. Two halves of "find it" behave
completely differently in Kubernetes:

- **The endpoint is cluster-wide.** `sqlserver.platform.svc.cluster.local,1433` resolves from any
  namespace. Verified by querying it from a pod in `default`.
- **The credential is not.** A Secret is namespace-scoped. `kubectl -n default get secret
  sqlserver-sa` returns NotFound, and no pod outside the platform's namespace can mount it.

So after `modules/rabbitmq` and `modules/sqlserver` were added, the answer to "where do I find the
connection details" was "ask whoever applied the Terraform" — the outputs live in a state file that
[ADR-PL-0003](./ADR-PL-0003-example-state-is-local-shared-environments-get-a-remote-backend.md)
deliberately keeps local and unshared.

This gap was not new. `papeete-deploy`'s `ADR-PD-0006` already says *"Whoever creates a namespace
creates its `imagePullSecrets`"* — the ACR pull credential has the same unautomated hand-off. Two
new modules made a third instance of a problem that already existed once.

The constraint that decides the shape of the answer: **the namespaces that need the credential do
not exist when the platform is applied.** Standing the same product up N times, per-PR and
per-branch, is something ADR-PL-0002 went out of its way to preserve. Any mechanism that takes a
list of consumer namespaces at apply time is stale the first time someone opens a pull request.

## Decision

**Each shared component publishes a per-tenant connection Secret**, at a well-known name
(`platform-<component>-<tenant>`), shaped so a pod can consume it whole with `envFrom`. It carries
the endpoint, the credential and the tenant's own vhost/database name.

**A cluster-wide controller mirrors those Secrets into consumer namespaces** —
[`modules/secret-reflector`](../modules/secret-reflector/), wrapping
emberstack/kubernetes-reflector. The source Secret carries `reflection-auto-enabled`, so the
controller pushes a copy into every namespace matching a regex **as that namespace appears**,
with nothing re-applied.

**The regex is the caller's declaration** (`reflect_to_namespaces`), null by default. A module with
no value set annotates nothing and its Secrets stay put — the reflector is opt-in, and the modules
work without it for a same-namespace consumer.

**A product's manifest names the Secret and nothing else.** No endpoint, no password, no knowledge
of how or where the platform was provisioned.

## Rationale

**Reflection over a caller-declared namespace list.** The list was the simpler option and needs no
new cluster component, but it cannot serve a namespace created after the apply — which is the
normal case here, not the edge case. A mechanism that requires a `terraform apply` per pull request
is a mechanism nobody will keep in sync.

**Reflection over papeete-deploy injecting it at deploy time.** `papeete-deploy` already creates
the namespace, so it is a plausible home for this. Rejected because it inverts this repo's
boundary: `papeete-deploy` consumes shared infra and never calls into this repo
([ADR-PL-0001](./ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)), so it would need
the platform's values fed to it by some other path — which is the original problem, moved.

**A published Secret rather than published Terraform outputs.** Outputs require the consumer to
read this repo's state. The Secret is in the cluster, where the consumer already is.

**One new shared component is an acceptable price** because it is precisely what this repo is for,
and because it retires the `ADR-PD-0006` hand-off too: `modules/acr`'s pull Secret can carry the
same annotations and stop being a manual step.

## Consequences

- **Verified on `docker-desktop`, not merely designed.** With `environments/local-platform`
  applied, a namespace created afterwards received all four connection Secrets within seconds and
  with no re-apply; a pod there reached the database through `envFrom` alone.
- **The regex is a trust boundary.** Every namespace matching it can read the credential. `.*` is
  right for a local cluster and wrong for a shared one, which should narrow it to the pattern its
  product namespaces follow.
- **A mirror is a copy.** Rotating a source credential updates mirrors, but a running pod keeps
  what it read until it restarts. Deleting the source deletes every mirror — so destroying the
  platform empties every consumer namespace, which is correct and still worth knowing.
- **Remains to realize: per-tenant credentials.** Every tenant's Secret currently carries the same
  `admin`/`sa` login, so a vhost or database is a namespace rather than a boundary, and any
  namespace matching the regex gets every tenant's Secret. Per-tenant logins are the fix, and they
  are a prerequisite before this shape is used anywhere that is not a local cluster.
- **Remains to realize: `modules/acr` does not yet publish this way.** Retiring the ADR-PD-0006
  hand-off is available but not done here.
- **A new top-level `environments/`.** `environments/local-platform` is a root module that owns
  its state and supplies its providers, not an umbrella module under `modules/` — that prohibition
  is unchanged. ADR-PL-0003 already anticipated environment-owning root modules.
