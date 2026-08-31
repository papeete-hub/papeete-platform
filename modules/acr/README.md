# `acr`

Creates an [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/) and
the two scope-mapped tokens an environment needs to use it: one that may **push** to a declared
set of repository paths, and one that may only **pull** from the same paths. Shared by every actor
and product deployed into that environment — nothing here names one of them
([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)); the
paths a token may reach are the caller's input.

This is the first module here to target a **cloud provider rather than a cluster**, and — with
[`modules/buildkit`](../buildkit/) — the first built from provider resources (`azurerm_*`) rather
than a `helm_release`: a registry has no chart to install. ADR-PL-0001 anticipated exactly this,
*"a module targets whatever provider its component needs"*, and
[ADR-PL-0002](../../adr/ADR-PL-0002-image-building-is-shared-platform-infrastructure.md) records
why image building is shared infrastructure at all.

As with every module in this repo, the `azurerm` provider is supplied by the caller — a root
module, or [`examples/acr-local`](../../examples/acr-local/) — so the subscription and credentials
stay an environment's concern, not the module's.

## Use directly

```hcl
provider "azurerm" {
  features {}
}

module "acr" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/acr?ref=v0.2.0"

  name                = "papeetefoundry"
  resource_group_name = azurerm_resource_group.this.name
  location            = "westeurope"
  repository_patterns = ["bnk.rlvr/*", "foundry/*"]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Registry name, 5–50 alphanumerics; becomes `<name>.azurecr.io` | *required* |
| `resource_group_name` | Existing resource group to create it in | *required* |
| `location` | Azure region | *required* |
| `repository_patterns` | Repository paths both tokens are scoped to, e.g. `["bnk.rlvr/*"]` | *required* |
| `sku` | Registry SKU — tokens need `Premium` | `"Premium"` |
| `admin_enabled` | Enable the registry's single admin account | `false` |
| `token_password_expiry` | RFC3339 expiry for both token passwords | `null` (never) |
| `tags` | Azure resource tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `login_server` | `<name>.azurecr.io` — what every image reference is composed from |
| `name` | Registry name, for `az acr` commands |
| `id` | Resource id, for role assignments the caller owns |
| `push_username` / `push_password` | The push token's credentials (password sensitive) |
| `pull_username` / `pull_password` | The read-only token's credentials (password sensitive) |

## Scoping

A scope map is a list of actions over repository paths, and this module derives two from
`repository_patterns`: `content/read`, `content/write`, `metadata/read` and `metadata/write` for
push, `content/read` and `metadata/read` for pull. Push includes read deliberately — a push mounts
layers the registry already holds rather than re-sending them, and fails without it.

A trailing `/*` matches everything below a path, so `bnk.rlvr/*` covers
`bnk.rlvr/sup.002.ben/backend` and `bnk.rlvr/sup.002.ben/backend/tests` alike. Neither token can
reach a repository outside the declared patterns, and neither can delete: retention is an
`az acr run --cmd "acr purge …"` operation under the caller's own credentials, not something a
build should be able to do by accident.

## Why tokens rather than a service principal

A token is a registry-local credential with no identity in the directory: it can be scoped to a
path prefix, rotated by replacing one resource, and handed to a cluster as a plain
`kubernetes.io/dockerconfigjson` Secret. A service principal would carry a directory identity and
RBAC across the whole registry to do the same job.

## Verified against

A single registry in one subscription. Geo-replication, private endpoints and customer-managed
keys are all deliberately absent — nothing needs them yet (ADR-PL-0001's Consequences).
