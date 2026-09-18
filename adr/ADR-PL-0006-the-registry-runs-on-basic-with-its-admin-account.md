---
id: ADR-PL-0006
title: "The registry runs on Basic with its admin account, not Premium with scope-mapped tokens"
status: Accepted
date: 2026-09-18
supersedes: []
references:
  - ../modules/acr/
  - ../examples/acr-local/
  - ./ADR-PL-0002-image-building-is-shared-platform-infrastructure.md
---

# ADR-PL-0006 — The registry runs on Basic with its admin account, not Premium with scope-mapped tokens

## Context

`modules/acr` was built on ACR's **Premium** SKU, for one feature: repository-scoped tokens. It
issued a push token and a read-only pull token over caller-declared `repository_patterns`, so a
builder could publish only under the paths it owned and a Pod's `imagePullSecret` could not write
at all. Scope maps and tokens exist on no lower tier, so the SKU was not a sizing choice — it was
the price of that credential model, and the module hard-defaulted to it.

The price turned out to be the whole bill. Month-to-date billing for `papeetefoundry`, 1–17
September 2026, was **€23.49 across 17 records, all of them the same meter** — `Premium Registry
Unit`, €1.43106/day, list $1.6666/day. No storage overage, no data-transfer meter, no ACR Tasks
minutes, no geo-replication. A full month runs ~€43.

Nothing else Premium sells was in use. `az acr show-usage` reported **4.86 GB** stored against
Premium's 500 GB allowance, zero geo-replications, zero private endpoints, customer-managed keys
disabled, zone redundancy off. The registry was paying a 500 GB, multi-region, private-networking
tier to hold 4.9 GB in one region and hand out two tokens.

## Decision

The registry runs on **Basic**, and its **admin account** is the credential.

`modules/acr` no longer creates scope maps, tokens or token passwords, and `repository_patterns`
and `token_password_expiry` are gone with them. `sku` defaults to `"Basic"`, `admin_enabled`
defaults to `true`, and the four token outputs collapse to one `username` / `password` pair. Every
consumer — the `acr-pull` Secret in `examples/acr-local`, `modules/buildkit`'s `registry_auth`, the
actor repos' release workflows — uses that one credential.

Per-repository scoping is given up deliberately, and so is the read-only pull credential, which is
the part that is easy to miss: on Basic there is no way to hand out read without also handing out
write.

## Rationale

The scoping was buying less than it looked like. One subscription, one registry, one developer, and
three path prefixes (`bnk.rlvr/*`, `foundry/*`, `reliever/*`) that all belong to the same person —
a token that cannot reach `reliever/*` is not defending a boundary between principals, it is
defending a boundary between one operator's own directories. €43/month is a poor price for that.

Standard (~€17/month) was considered and rejected: it drops tokens too, so it costs four times
Basic to buy nothing this registry uses — its only gain over Basic is 100 GB of included storage
against 10 GB, and the registry holds 4.9 GB.

The alternative that *keeps* the push/pull split without Premium is an Entra service principal per
role — `AcrPush` for the builder, `AcrPull` for the kubelet — which works on any tier and costs
nothing. It was rejected **for now**, not on the merits: it adds the `azuread` provider and
directory identities to a module whose README previously argued against exactly that, and it
requires app-registration rights in the tenant. It remains the right answer if a second principal
ever touches this registry, and it is the first thing to reach for instead of re-upgrading the SKU.

## Consequences

- **Bill drops from ~€43/month to ~€4.30/month.** Basic is $0.167/day list.
- **The `acr-pull` Secret can now push.** Anything that can read it can overwrite any tag,
  including one it does not own. This is the real cost of the decision; `modules/acr`'s README
  states it at the point of use rather than leaving it to this ADR.
- **Rotation is registry-wide and has no overlap window.** `az acr credential renew` invalidates
  the credential for the pull Secret, the builder and CI simultaneously. Staging a rotation means
  using `password2` deliberately.
- **10 GB included storage, not 500.** At 4.9 GB there is headroom, not a lot of it, and nothing
  here schedules retention — `az acr show-usage -n papeetefoundry` is the check, and
  `az acr run --cmd "acr purge …"` the remedy.
- **The move plans as 2 changes and 6 destroys**, verified against the live registry: tokens,
  token passwords and scope maps destroyed, SKU and `admin_enabled` changed in place, the
  `acr-pull` Secret rewritten. Azure documents geo-replications and connected registries as
  downgrade blockers — this registry has neither — and does not name tokens. **Applied 2026-09-18
  and it carried in one apply**, no targeted destroy needed: 2 changed, 6 destroyed, registry
  `Premium -> Basic` with `admin_enabled true`.
- **But the credential needs a second apply.** Enabling the admin account and reading its username
  and password in one apply returns empty strings — Azure creates them during the update and the
  provider answers from before that. The first apply therefore wrote an *empty* credential into the
  `acr-pull` Secret while reporting success. The second apply fixed it (`username = "" ->
  "papeetefoundry"`), and the registry then answered `200` on `/v2/_catalog` with 30 repositories
  visible. `modules/acr`'s README carries the detail and the check.
- **Follow-ups outside this repo, which this ADR does not perform.** The actor repos hold the push
  credential as GitHub secrets `ACR_PUSH_USERNAME` / `ACR_PUSH_PASSWORD`
  (`foundry-implementation-actor`, `foundry-testing-actor`, `foundry-task-orchestration-actor`);
  each must be reset to the admin credential or releases stop.
  `foundry-implementation-actor`'s `ADR-FIA-0006` describes the scope-map requirement as a live
  constraint and is now stale in that respect.
