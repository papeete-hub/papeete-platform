---
id: ADR-PL-0003
title: "Example state is local and never shared; a shared environment gets a remote backend when there is one"
status: Accepted
date: 2026-09-16
supersedes: []
references:
  - .gitignore
  - examples/acr-local/main.tf
  - examples/observability-local/main.tf
---

# ADR-PL-0003 — Example state is local; shared environments get a remote backend

## Context

Every `examples/<name>-local/` is applied by a person, on their own machine, against their own
Docker Desktop cluster — and `examples/acr-local` additionally against **their own Azure resource
group**. Two people running the same example instantiate genuinely different infrastructure: a
different `azurerm_resource_group`, a different registry name, different tokens.

A `terraform.tfstate` records which objects an apply created. Sharing one between two such people
does not share infrastructure — it makes each one's next `plan` propose destroying the other's.
The examples declare no `backend` block at all, so Terraform uses the local backend and writes
`terraform.tfstate` next to the example.

## Decision

**Example state stays on the machine that produced it, and is never committed.** `.gitignore`
excludes `*.tfstate`, `*.tfstate.*` and `.terraform/`; nothing matching them is tracked, and
nothing should become tracked.

**No example declares a `backend`.** An example demonstrates a module against a throwaway local
cluster; it is not an environment, and it has no state worth keeping past `terraform destroy`.

**A shared environment — when there is one — gets a remote backend, and it is declared by whatever
root module owns that environment, not by an example here.** For the Azure-targeting modules that
means an `azurerm` backend: a Storage Account container holding the state blob, with per-environment
state keys and the blob's own lease as the lock.

## Rationale

Local state is not a stopgap that a backend later corrects; it is the right answer for a per-person
throwaway apply. The two cases are different in kind, not in maturity:

- An **example** has exactly one operator, no concurrency, and its whole lifetime is one
  `apply`/`destroy` pair. Remote state would add an Azure dependency to `terraform init` for a
  module that may not target Azure at all, and would need a bootstrap chicken-and-egg (who creates
  the Storage Account?) to demonstrate a Helm chart on Docker Desktop.
- A **shared environment** has several operators and CI, so it needs exactly what a remote backend
  provides: one authoritative state and a lock preventing two concurrent applies.

Putting the backend in the environment's own root module rather than here also keeps this repo's
boundary intact (ADR-PL-0001): a module never configures its own provider, and by the same logic it
never configures the state of an environment it does not own.

## Consequences

- **CI never needs credentials for state.** `.github/workflows/ci.yml` runs
  `terraform init -backend=false`, which is what makes `validate` possible with no cloud account.
- **`terraform destroy` is the only cleanup.** Losing a local `terraform.tfstate` orphans whatever
  it tracked — for `examples/acr-local` that means real Azure resources still billing. Destroy
  before discarding a working copy.
- **Remains to realize.** Nothing here creates the Storage Account, container, or the naming
  convention for state keys, because no shared environment exists yet. When the first one does, it
  needs a decision on where that bootstrap lives — plausibly its own ADR, since the Storage Account
  holding every environment's state cannot itself be held in one of those states.
- **Local state is not encrypted at rest.** `examples/acr-local`'s state contains the ACR token
  passwords in clear text, as Terraform state always does for generated secrets. That is another
  reason it is ignored rather than merely uncommitted — and a reason to `destroy` rather than keep
  it lying around.
