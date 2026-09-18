# `artifacts-feed-local`

The worked example: [`modules/artifacts-feed`](../../modules/artifacts-feed/) applied to the
`papeete-consulting` organization, producing the `papeete-python` feed that the `papeete-hub`
repositories publish to and resolve from.

"local" names **where the state lives**, not what the feed serves. Every other example here runs
against a developer's Docker Desktop cluster; this one has no cluster at all. The feed is
organization-scoped and serves the CI of seventeen repositories — it is the *example* that is local,
applied from a workstation with local state ([ADR-PL-0003](../../adr/ADR-PL-0003-example-state-is-local-shared-environments-get-a-remote-backend.md)).

```bash
az login
export AZDO_PERSONAL_ACCESS_TOKEN=<Packaging read/write/manage + Identity read>
terraform init
terraform apply
```

`az login` is for two things: the `azuread` provider, which creates the applications and their
federated credentials, and the `az rest` call that configures the upstream. The PAT is only for the
`azuredevops` provider, which cannot use that login — see below.

That creates the feed with PyPI as its upstream, two Entra applications with a federated credential
each, two Azure DevOps service principals holding Basic licenses, and their feed permissions. Then
the three values every repository needs:

```bash
terraform output -json github_organization_variables \
  | jq -r 'to_entries[] | "\(.key)=\(.value)"' \
  | while IFS='=' read -r key value; do gh variable set "$key" --org papeete-hub --body "$value"; done
```

## Narrow in, broad out

The two identities are scoped very differently, on purpose:

| | Pattern | Role |
|---|---|---|
| publish | `repo:papeete-hub/*:environment:azure-artifacts` | `contributor` |
| consume | `repo:papeete-hub/*` | `collaborator` |

Publishing requires a run that went through the `azure-artifacts` GitHub environment. That
environment is also where the restriction to release tags lives: an environment-scoped subject
carries no ref, so the credential alone cannot tell a tag from a branch — the environment's tag
protection rule (`v*`) can, and it is the caller's to create in each repository.

Resolving is open to every branch and every pull request in the organization, because every one of
them installs dependencies before it does anything else. The breadth costs little: the consuming
identity is a `collaborator`, so it can read the feed and pull a third-party package through the
upstream, and it cannot publish a package of its own.

Both expressions also pin `repository_owner_id` to `301756401`. Entra requires an immutable claim
alongside `sub`, and the numeric id is the useful kind of immutable — a pattern written against the
organization's *name* would still match if that name were ever given up and re-registered.

## The PAT, and why it is the only one

The `azuredevops` provider cannot authenticate from an `az login`; the request has been open since
2021. So an apply needs a personal access token, scoped to **Packaging** (read/write/manage) and
**Identity** (read), read from `AZDO_PERSONAL_ACCESS_TOKEN`.

It stays on the operator's machine and never becomes a GitHub secret. CI does not use it and has no
way to: a workflow logs in with `azure/login`, exchanges its OIDC token for an Entra token against
`499b84ac-1321-427f-aa17-267ca6975798`, and hands that to the feed as a password that expires in an
hour. Give the PAT a short expiry and re-issue it when you next need to apply.

## Before anything publishes

Applying this is safe. **Publishing to the feed is a one-way door**, and it is not this example's to
open: the first internal version of a package makes every version of it that lives only on pypi.org
unreachable through the feed, including the ones the committed lock files pin. Every pinned version
has to be pulled through the feed first, which caches it permanently. `modules/artifacts-feed`'s
README explains the mechanism; the migration plan owns the sequencing.

Resolving, by contrast, is free to try immediately, and is the right way to check the upstream works:

```bash
token=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv)
pip download --no-deps --dest /tmp/probe \
  --index-url "https://dummy:${token}@pkgs.dev.azure.com/papeete-consulting/_packaging/papeete-python/pypi/simple/" \
  "packaging==24.2"
```

The wheel comes from PyPI through the feed, and afterwards `packaging 24.2` is listed in the feed as
an upstream-sourced version.

## Destroying

`terraform destroy` removes the feed and both identities. The feed's name is then **reserved for up
to 15 minutes**, so an immediate re-apply under the same name fails; wait it out rather than picking
a different name.
