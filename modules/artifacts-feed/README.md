# `artifacts-feed`

Creates an [Azure Artifacts](https://learn.microsoft.com/azure/devops/artifacts/) feed that serves
as **the** Python index for an organization — its own packages and, through an upstream, everything
it takes from PyPI — plus the two federated identities that reach it: one that may **publish**, and
one that may only **resolve** and cache from the upstream. Shared by every repository that builds or
ships Python, and named by none of them
([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)); which
workflows may reach it is the caller's input.

Like [`modules/acr`](../acr/), this targets a cloud service rather than a cluster, and it is built
from provider resources rather than a `helm_release`. Unlike `modules/acr`, **it emits no secret at
all**: both credentials are Entra applications a GitHub workflow assumes through OIDC, so the thing
a workflow needs from this module is a client id, and the thing it gets from Entra expires in an
hour. [ADR-PL-0005](../../adr/ADR-PL-0005-the-python-index-is-a-private-feed-that-proxies-pypi.md)
records why the index moved off pypi.org.

The `azuread` and `azuredevops` providers are supplied by the caller — a root module, or
[`examples/artifacts-feed-local`](../../examples/artifacts-feed-local/) — so the tenant and the
organization's credentials stay an environment's concern.

## Use directly

```hcl
provider "azuread" {}

provider "azuredevops" {
  org_service_url = "https://dev.azure.com/papeete-consulting"
}

module "artifacts_feed" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/artifacts-feed?ref=v0.3.0"

  organization_name          = "papeete-consulting"
  name                       = "papeete-python"
  github_repository_owner_id = "301756401"

  publisher_subject_patterns = ["repo:papeete-hub/*:environment:azure-artifacts"]
  consumer_subject_patterns  = ["repo:papeete-hub/*"]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `organization_name` | Azure DevOps organization the feed is created in | *required* |
| `publisher_subject_patterns` | GitHub OIDC `sub` patterns allowed to publish | *required* |
| `consumer_subject_patterns` | `sub` patterns allowed to resolve and cache from upstreams | *required* |
| `github_repository_owner_id` | Numeric GitHub organization id, the immutable claim Entra demands | *required* |
| `name` | Feed name, and the segment packages are addressed under | `"papeete-python"` |
| `upstream_sources` | Sources the feed proxies | one `PyPI` public source |
| `configure_upstream_sources` | Apply the upstream configuration through `az rest` | `true` |
| `oidc_issuer` | Issuer the credentials trust | GitHub Actions |
| `oidc_audience` | Audience the incoming token must carry | `"api://AzureADTokenExchange"` |
| `retention_count_limit` | Versions kept per package | `50` |
| `retention_days_to_keep_recently_downloaded_packages` | Grace period for a version still in use | `30` |
| `account_license_type` | Azure DevOps license for both service principals | `"express"` |
| `azure_devops_resource_id` | Entra application id of Azure DevOps | the well-known constant |

There is **no `tags` variable**, and that is not an oversight: an Azure DevOps feed is not an ARM
resource and carries no tags.

## Outputs

| Name | Description |
|---|---|
| `index_url` | `…/pypi/simple/` — the single index to resolve against |
| `publish_url` | `…/pypi/upload/` — `uv publish`'s `publish-url`, twine's `TWINE_REPOSITORY_URL` |
| `feed_id` / `feed_name` | The feed, for packaging API calls and for the Artifacts view |
| `publish_client_id` / `consume_client_id` | The two identities, as GitHub organization variables |
| `publish_service_principal_object_id` / `consume_service_principal_object_id` | How each appears under *Organization settings → Users* |
| `tenant_id` | Entra tenant both identities live in |
| `azure_devops_resource_id` | The `--resource` that turns an Entra login into a feed password |

**Not one of them is `sensitive`,** and that is the whole difference from `modules/acr`. There, the
two tokens' passwords are the outputs that matter and both are marked sensitive. Here the outputs
are client ids and a tenant id — public identifiers, useless without a token federated from a
workflow whose subject matches.

## The feed is organization-scoped

`azuredevops_feed` takes an optional `project_id`, and this module never passes one. A project-scoped
feed belongs to a project and is reached through its path; this feed is shared by every repository in
the organization and belongs to none of them. The Azure DevOps organization does have a project —
creating one is unavoidable — but the feed deliberately does not live in it.

That choice is also what fixes the URLs: `https://pkgs.dev.azure.com/<org>/_packaging/<feed>/pypi/…`
with no project segment.

## The upstream sources are a `local-exec`, and why that is stable

The `azuredevops` provider's feed schema is `name`, `project_id` and two delete flags. It cannot
express an upstream source, an upstream-enabled flag, or a name-conflict policy. So
`terraform_data.upstream_sources` issues one `PATCH` against the packaging REST API, in the shape
[`examples/acr-local`](../../examples/acr-local/) already established for reaching past a provider:
an explicit interpreter, a `count` flag to turn it off, and nothing interpolated into the command —
every dynamic value goes through `environment` and is read as `"$VAR"`.

Ordinarily that would be a race, with the provider overwriting the hand-written state on the next
apply. It is not one here, for a precise reason: the provider sends the name alone on create and an
**empty object** on update, so it never transmits these fields and never clears them. The hybrid is
stable, and `terraform plan` right after an apply proves it by reporting no drift.

The REST host is `feeds.dev.azure.com`, not `dev.azure.com`. The packaging endpoints do not exist
under the organization's own host, and a `PATCH` there returns 404.

## Publishing is a one-way door, per package

Once an internal version of a package exists in the feed, versions of that package that live only
upstream stop being reachable through it. Unblocking one afterwards is a
`PATCH .../pypi/packages/<name>/upstreaming` per package, and up to three hours of propagation. A
version already **cached** in the feed, by contrast, stays reachable forever.

So every version anything pins has to be pulled through the feed **before** the first internal
publish of that package. This module opens the feed; it does not warm it, and applying it does not
start the clock.

Azure Artifacts has a feed-level `allowUpstreamNameConflict` that sounds like it belongs here. It
does not: it is gated behind the `Packaging.Feed.Npm.AllowUpstreamNameConflict` feature, a `PATCH`
carrying it fails with `FeatureDisabledException` on a feed like this one, and the name says which
protocol it was built for. Whether a PyPI feed refuses an internal package whose name also exists
upstream is therefore **not settled here** — the first publish of the pilot package is what settles
it, and it must happen after the feed is warm either way.

## The consumer is a collaborator, not a reader

Azure DevOps feed roles run `reader` < `collaborator` < `contributor` < `administrator`, and only
`collaborator` and above may *save* a package from an upstream into the feed. A `reader` can read
what is already cached and nothing else, so it fails on the first cache miss — which, on day one, is
every third-party dependency. The publishing identity is a `contributor`, which contains
`collaborator`; it can add packages but cannot change feed settings.

## What the caller still owns

- **The organization, and the member user that owns it.** Neither is an ARM resource; no provider
  creates them. The same boundary as `modules/acr`'s `resource_group_name`.
- **A PAT for the `azuredevops` provider.** It cannot authenticate from an `az login`, so an apply
  needs a personal access token. Four scopes, measured rather than guessed — **Packaging**
  (read/write/manage), **Identity** (read), **Member Entitlement Management** (read & write) and
  **Graph** (read). The first two alone create the feed and then fail on the entitlements, which is
  the trap: the failure lands halfway through an apply. It is the one long-lived secret this design
  does not remove, it belongs on the operator's machine, and it never belongs in CI — CI
  authenticates through the identities this module creates.
- **A directory role for whoever applies this.** Creating an application and a service principal
  needs no role; **deleting a service principal does**, and owning the application is not enough.
  Without **Application Administrator** (or Cloud Application Administrator) the apply succeeds and
  the destroy fails with `Authorization_RequestDenied`, so the gap shows up at the worst moment.
- **The GitHub side.** The environment named in `publisher_subject_patterns` has to exist in every
  publishing repository, with whatever protection rule restricts it to a release — an
  environment-scoped subject carries no ref, so the environment is where that restriction lives. The
  organization variables carrying the two client ids and the tenant id are `gh variable set`.

## Verified against

Applied once, against the `papeete-consulting` organization: the feed came up organization-scoped
with PyPI attached and `status: ok`, `terraform plan` immediately afterwards reported no drift — the
out-of-band `PATCH` is not reclaimed — and `uv` resolved a third-party package through the feed,
which then held it as a cached version. Feed views, project-scoped feeds, internal upstreams and
per-package upstream policies are all absent because nothing needs them yet.

**Not yet exercised: the two identities themselves.** They can only be assumed from a GitHub Actions
run, so the checks above were made with an operator's own credentials. That the `collaborator` role
is enough to save from an upstream, and that the `contributor` role is enough to publish, are
claims this module makes and the first workflow run tests.
