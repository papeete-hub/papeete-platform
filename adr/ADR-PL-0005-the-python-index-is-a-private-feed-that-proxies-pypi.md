---
id: ADR-PL-0005
title: "The organization's Python index is a private Azure Artifacts feed that proxies PyPI"
status: Accepted
date: 2026-09-18
supersedes: []
references:
  - modules/artifacts-feed/main.tf
  - examples/artifacts-feed-local/main.tf
---

# ADR-PL-0005 — The Python index is a private feed that proxies PyPI

## Context

Seventeen repositories in the `papeete-hub` organization publish Python distributions to **public
pypi.org**, each from its own copied `release.yml`. Counted, not estimated: twelve use `uv publish
--trusted-publishing always`, five use `pypa/gh-action-pypi-publish`, and all seventeen trigger on a
`v*` tag. Four of them — `kcapture`, `kmint`, `kontract`, `kpack` — declare
`license = { text = "Proprietary" }` and are published to the public index anyway.

Nothing in the organization configures an index. Fifteen committed `uv.lock` files pin every
dependency to `source = { registry = "https://pypi.org/simple" }`, and seven Dockerfiles install
with pip's defaults. There is no place today where the question "where do packages come from" is
answered once.

Two facts about the credentials shape what could replace it:

- **The publishing side already has no secrets.** All seventeen publish through OIDC Trusted
  Publishing. Any replacement that reintroduced a stored API token would be a regression, not a
  migration.
- **Thirteen of the seventeen gate publishing behind a GitHub environment; the four `k*` repos do
  not.** Their runs present `repo:papeete-hub/kmint:ref:refs/tags/v0.1.1`, with no environment
  segment at all.

This repo already owns the analogous decision for images —
[`modules/acr`](../modules/acr/) and
[ADR-PL-0002](./ADR-PL-0002-image-building-is-shared-platform-infrastructure.md) — so a private
Python index is the same kind of shared, cross-product infrastructure, in the one artifact class
that was still public.

## Decision

**The organization's Python index is one Azure Artifacts feed with pypi.org configured as an
upstream source**, provisioned by [`modules/artifacts-feed`](../modules/artifacts-feed/). It
replaces pypi.org rather than sitting beside it: consumers point at it as their default index and
reach PyPI only through it.

**The feed is organization-scoped, not project-scoped.** It is shared by every repository and
belongs to none of them, which is the same boundary every module here draws.

**Two Entra applications reach it, federated from GitHub Actions** — one `contributor` that may
publish, one `collaborator` that may resolve and cache from the upstream. Each carries a *flexible*
federated identity credential, so one expression covers all seventeen repositories instead of
seventeen credentials against a cap of twenty.

**A GitHub environment is the publishing gate, in all seventeen repositories.** The four `k*` repos
gain the environment they do not have today, so that a single subject pattern —
`repo:papeete-hub/*:environment:azure-artifacts` — is the whole publishing rule, and the
environment's tag protection is what confines it to a release.

**The upstream configuration is a `PATCH` in a `local-exec`.** The `azuredevops` provider's feed
schema cannot express an upstream, so `terraform_data.upstream_sources` calls `az rest`, in the shape
[`examples/acr-local`](../examples/acr-local/) established.

**Existing versions on pypi.org stay there.** Nothing is migrated and nothing is deleted.

## Rationale

**A proxying feed over a second index.** Adding a private index beside PyPI is the smaller change,
and it is the one that keeps dependency confusion alive: with two indexes in the resolution path,
anyone who publishes `papeete-actor 99.0.0` to the public one can win. A single index that proxies
the public one has exactly one answer per name.

**Azure Artifacts over a hosted private index.** The organization already runs in this tenant, the
subscription that holds `papeetefoundry` is the same one, and the feed inherits the directory's
identities rather than needing its own account model. Gemfury and a self-hosted devpi were the
alternatives; both would have added a credential store this design otherwise does not have.

**Federated service principals over a PAT in CI.** A PAT would have worked immediately and is what
most Azure Artifacts documentation assumes. It would also have put a long-lived secret into
seventeen repositories to replace a scheme that had none. The workflow logs in with `azure/login`,
exchanges its OIDC token for an Entra token, and hands that to the feed as a password valid for an
hour.

**Client ids as outputs, where `modules/acr` emits passwords.** This is the one place this module is
plainly better than its own precedent, and it is worth naming: `modules/acr` has to mark four
outputs `sensitive` because a registry token *is* its password. Here every output is a public
identifier.

**Flexible federated identity credentials over seventeen classic ones.** Classic credentials match a
subject exactly and cap at twenty per application, which would have left three spare — no room for a
new repository, a second environment, or a mistake. Microsoft's own documentation states that
Terraform providers do not support flexible credentials; that has been false since `azuread` 3.7.0,
and it was verified against this tenant before the module was written (below).

**Organization-scoped over project-scoped.** A project had to be created to hold the organization,
but the feed does not live in it: seventeen repositories share the feed and none of them maps to
that project.

## Consequences

- **Verified against a live tenant, not merely designed.** An `azuread_application_registration` plus
  an `azuread_application_flexible_federated_identity_credential` were applied, re-planned and
  destroyed in the `Default Directory` tenant. The apply succeeded, the re-plan reported *No
  changes*, and Graph returned the expression stored with `subject: null` and `languageVersion: 1`.
  The provider reads the expression back faithfully, so the credentials do not drift.
- **The flexible credential is a preview feature on a beta endpoint.** The provider writes it
  through `graph.microsoft.com/beta`. A breaking change there breaks this module, and the fallback is
  known and costed: seventeen classic credentials in a `for_each`, seventeen of twenty slots used.
- **The upstream configuration lives outside the provider's model.** It survives because
  `azuredevops_feed` transmits the name alone on create and an empty object on update, so an apply
  never clears what the `PATCH` set. That is a property of the current provider, not a guarantee —
  `terraform plan` immediately after an apply is the check that it still holds.
- **One long-lived secret remains: the bootstrap PAT.** The `azuredevops` provider cannot
  authenticate from an `az login`. Applying this module therefore needs a personal access token
  scoped to Packaging and Identity, on the operator's machine. It is never a GitHub secret, and CI
  has no use for it.
- **Storage is now a shared, finite resource.** An organization gets 2 GiB free, every third-party
  wheel pulled through the upstream is stored against it, and a deleted package still counts for 30
  days. The module sets a retention policy by default; billing has to be attached to the
  subscription before the feed is used in anger.
- **Each service principal consumes an Azure DevOps license.** Five Basic licenses are free and this
  module takes two of them.
- **Publishing is a one-way door, per package.** The first internal version of a package makes every
  version of it that lives only on pypi.org unreachable through the feed — including the versions the
  fifteen committed lock files pin. Reversing it is a `PATCH .../upstreaming` per package and up to
  three hours of propagation. Conversely, `allow_upstream_name_conflict` has to be on or the first
  publish fails, because all seventeen names already exist upstream.
- **Remains to realize: the feed must be warmed before anything is published to it.** Every version
  the lock files pin has to be pulled through the feed first, which caches it permanently. This
  module opens the feed; it does not warm it, and applying it does not start the clock.
- **Remains to realize: the seventeen `release.yml` files, and the GitHub environment.** No workflow
  changed here. The `azure-artifacts` environment has to exist in all seventeen repositories, with a
  `v*` tag protection rule, before the publishing credential means anything.
- **Remains to realize: `kcapture` runs outside CI.** It is installed with `uvx` on workstations that
  have no Entra identity, so those machines need a credential path of their own — and existing
  installations stop seeing new versions the moment it leaves pypi.org. That is the accepted cost of
  moving it, and it has to be solved before the public Trusted Publishers are removed.
- **Out of scope, and worth stating: `git+https://` installs never touched an index.** The plugin
  skills' `projectors` pin and `kmint`'s `Makefile` reference to `kledger` are unaffected by any of
  this.
