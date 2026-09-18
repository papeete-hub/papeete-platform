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
| `allow_upstream_name_conflict` | Accept a package whose name also exists upstream — see below | `true` |
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

## `allow_upstream_name_conflict`, which cuts both ways

Azure Artifacts refuses, by default, to accept a package whose name already exists in an upstream.
Every package this feed exists to serve is also on pypi.org, so without this flag the first publish
of any of them fails outright. It defaults to `true` because the alternative is a feed that cannot
be published to.

The same mechanism runs the other way, and that direction is **not** configurable: once an internal
version of a package exists in the feed, versions of that package that live only upstream stop being
reachable through it. Unblocking one afterwards is a `PATCH .../pypi/packages/<name>/upstreaming`
per package and up to three hours of propagation.

A version already **cached** in the feed stays reachable forever. So every version anything pins has
to be pulled through the feed **before** the first internal publish. That is a one-way door, and it
is the caller's to walk through — this module opens the feed, it does not warm it.

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
  needs a personal access token scoped to Packaging and Identity. It is the one long-lived secret
  this design does not remove, it belongs on the operator's machine, and it never belongs in CI —
  CI authenticates through the identities this module creates.
- **The GitHub side.** The environment named in `publisher_subject_patterns` has to exist in every
  publishing repository, with whatever protection rule restricts it to a release — an
  environment-scoped subject carries no ref, so the environment is where that restriction lives. The
  organization variables carrying the two client ids and the tenant id are `gh variable set`.

## Verified against

One organization, one organization-scoped feed, one public PyPI upstream, two identities. Feed
views, project-scoped feeds, internal upstreams pointing at another feed, and per-package upstream
policies are all absent because nothing needs them yet. The flexible federated identity credentials
were exercised against a live tenant before the module was written — see ADR-PL-0005 for what that
proved and what it left in preview.
