# `acr`

Creates an [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/) on the
**Basic** SKU and enables its admin account, which is the one credential an environment uses to
push to it and pull from it. Shared by every actor and product deployed into that environment —
nothing here names one of them
([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)).

It used to issue two scope-mapped tokens instead, a push and a read-only pull, over caller-declared
repository paths. That needed the Premium SKU, which is a flat ~€43/month whatever the registry
holds — measured at €23.49 for the first 17 days of September 2026 against 4.9 GB stored, with no
other meter on the bill.
[ADR-PL-0006](../../adr/ADR-PL-0006-the-registry-runs-on-basic-with-its-admin-account.md) records
the trade that ended: per-repository scoping and a read-only pull credential, for a tenth of the
price.

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
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/acr?ref=v0.3.0"

  name                = "papeetefoundry"
  resource_group_name = azurerm_resource_group.this.name
  location            = "westeurope"
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Registry name, 5–50 alphanumerics; becomes `<name>.azurecr.io` | *required* |
| `resource_group_name` | Existing resource group to create it in | *required* |
| `location` | Azure region | *required* |
| `sku` | Registry SKU — the entire cost of this module | `"Basic"` |
| `admin_enabled` | Enable the registry's single admin account — see below | `true` |
| `tags` | Azure resource tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `login_server` | `<name>.azurecr.io` — what every image reference is composed from |
| `name` | Registry name, for `az acr` commands |
| `id` | Resource id, for role assignments the caller owns |
| `username` / `password` | The admin account's credentials (password sensitive), null unless `admin_enabled` |

## What the admin account is, and what it costs you

One credential, registry-wide, with no scoping. Everything that touches the registry uses it: the
builder that pushes, and the `imagePullSecret` a Pod pulls with. Two things follow, and neither is
hypothetical:

- **A Pod's pull Secret can push.** There is no read-only credential on this tier. Anything that
  can read that Secret can overwrite any tag in the registry, including one it does not own.
- **Rotation is registry-wide and instant.** `az acr credential renew --name <registry>
  --password-name password` invalidates the credential everywhere at once — the pull Secret, the
  builder's `config.json` and the CI secrets in the actor repos. There is no overlap window unless
  you use `password2` to stage one.

`admin_enabled` therefore defaults to `true` because the module has nothing else to offer, not
because it is a good credential. If an environment needs the push/pull split back, the cheap way is
not Premium — it is an Entra service principal per role (`AcrPush`, `AcrPull`), which works on
Basic and which ADR-PL-0006 records as the deliberate follow-up.

## Enabling the admin account takes two applies

**Measured, applying this against the live registry.** Turning `admin_enabled` from `false` to
`true` and reading `admin_username` / `admin_password` in the *same* apply yields **empty strings**,
not credentials. Azure creates them as part of the update, and the `azurerm` provider composes its
result from a response that predates them. Terraform reports `Apply complete!` and every consumer
of those outputs is silently wired to `""`.

That is not cosmetic: on the first apply here, `examples/acr-local`'s `acr-pull` Secret was rewritten
with an empty username and a zero-length password — a Secret that exists, looks right to
`kubectl get`, and cannot pull. A second `terraform apply` refreshes the registry, finds the
credentials and plans a one-resource change to fix it:

```
~ username = "" -> "papeetefoundry"
```

So an environment that enables the admin account must apply twice, and the check that it worked is
the credential itself rather than Terraform's exit code:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -u "$(terraform output -raw username):$(terraform output -raw password)" \
  https://<registry>.azurecr.io/v2/_catalog        # 200, not 401
```

This does not apply to a registry created with `admin_enabled = true` from the start — only to
flipping it on an existing one, which is exactly what the move off Premium does.

## Storage

Basic includes **10 GB**; beyond that ACR bills per GB/day. This registry held 4.9 GB when it moved
tiers, and retention is an `az acr run --cmd "acr purge …"` operation under the caller's own
credentials — nothing here schedules it, so watch `az acr show-usage -n <registry>` rather than
assuming the headroom is permanent.

## Verified against

A single registry in one subscription. Geo-replication, private endpoints and customer-managed keys
are all deliberately absent — they are Premium features and nothing needs them (ADR-PL-0001's
Consequences). The `hosts.toml` node bypass that makes pulls work on Docker Desktop is unaffected
by the tier and is explained in [`examples/acr-local`](../../examples/acr-local/).
