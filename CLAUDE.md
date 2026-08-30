# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Terraform modules for infrastructure **shared across actors and products** in the `papeete-*`
ecosystem — installed once per cluster/environment, owned by no single actor/product. See
[ADR-PL-0001](./adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md) and the
README for the full boundary rationale. In short:

- **A module here never takes an actor or product identity as input.** If a variable would only
  ever be set to one actor's name, it belongs in that actor's own `deploy/terraform/`
  (`papeete-actor`'s `ADR-PA-0025`), not here.
- **This repo provisions; `papeete-deploy` consumes.** `papeete-deploy` assumes an environment's
  shared infra already exists — it never calls into this repo.
- **Orthogonal to any PCM-designed domain-specific platform** (e.g. a banking platform). No
  dependency in either direction; nothing here reads a PCM artefact.
- Not Kubernetes-exclusive by design, even though every module today targets `kubernetes`/`helm`.

## Commands

Each module and its example is validated independently (mirrors `.github/workflows/ci.yml`'s
matrix — check that file for the current list of directories):

```bash
terraform fmt -check -recursive          # from repo root; run without -check to auto-fix
cd modules/<name> && terraform init -backend=false && terraform validate
cd examples/<name>-local && terraform init -backend=false && terraform validate
```

`validate` only checks syntax/schema — it needs no live cluster. To actually deploy an example
against Docker Desktop's Kubernetes:

```bash
cd examples/<name>-local
kubectl config use-context docker-desktop
terraform init
terraform apply
terraform destroy
```

Releasing a module: modules are consumed by git ref, not a package registry —
`git tag vX.Y.Z && git push origin vX.Y.Z`.

## Architecture

**One independently-deployable root module per shared component**, under `modules/<name>/`
(`main.tf` / `variables.tf` / `outputs.tf` / `README.md`), each paired with a worked
`examples/<name>-local/` that supplies a `helm`/`kubernetes` provider pointed at `docker-desktop`
and instantiates the module directly (`source = "../../modules/<name>"`). No wrapper or umbrella
stack combining modules. A module never configures its own provider — the caller always supplies
it, which is what keeps a module reusable across environments.

Within a module, every `helm_release` follows the same per-resource variable shape:
`chart_version` (nullable, unpinned = latest), `set_values` (map, `--set`-style, via a `dynamic
"set"` block) and `values_yaml` (a full values document as a string). A module with several
components (e.g. `modules/observability`) gates each `helm_release` behind its own
`enable_<component>` boolean and prefixes its three variables per component
(`<component>_chart_version` etc.), so pieces can be turned off independently. Where a component
needs an opinionated default `values.yaml` to actually be wired to its siblings (not just the
chart's own defaults), that default lives in a `locals.<component>_default_values` heredoc and is
layered under any caller-supplied `values_yaml` — `values = [local.default, var.values_yaml]` when
an override is given, `[local.default]` alone otherwise — so a caller can extend rather than fully
replace the default.

### `modules/observability`

OTel Collector receives OTLP over **gRPC on 4317** and fans out to **Tempo** (traces), **Loki**
(logs, via OTLP push — no Promtail/Fluent-bit needed) and its own Prometheus exporter, scraped by
the **Prometheus** release. **Grafana** ships with all three pre-provisioned as datasources,
including trace-to-logs correlation (Loki's derived field → Tempo; Tempo's `tracesToLogsV2` →
Loki), plus a ConfigMap sidecar that auto-discovers dashboards products ship in their own
namespaces (`sidecar.dashboards.searchNamespace: ALL` — deliberately cluster-wide, not
`var.namespace`, since dashboards live in product namespaces, not this module's). A product opts a
dashboard ConfigMap in via the `grafana_dashboard: "1"` label; `grafana_folder` annotation files it
into a named folder. Elasticsearch + Kibana are a second, opt-in log store
(`enable_elasticsearch_kibana`, default `false`) — genuinely different from Loki, not a
replacement, and off by default.

**Chart quirks discovered by actually deploying this against `docker-desktop`** (not visible from
`terraform validate` alone — worth knowing before touching `main.tf`'s `locals`):
- `opentelemetry-collector`'s fullname template appends the chart name unless the release name
  already contains it, so the release name `otel-collector` alone would produce a service named
  `otel-collector-opentelemetry-collector`. `fullnameOverride: otel-collector` pins it to the
  short name every other component's default values (and every actor's `OTEL_EXPORTER_OTLP_ENDPOINT`)
  depend on.
- `prometheus-community/prometheus`'s `extraScrapeConfigs` is a **top-level** values key, not
  nested under `server:` — nesting it there is silently ignored (no error, just never scraped).
- `grafana/loki`'s `SingleBinary` deployment mode still validates the `read`/`write`/`backend`
  (simple-scalable) replica counts; leaving their chart defaults nonzero fails the chart's own
  `validate.yaml` even though `deploymentMode: SingleBinary` is set. Zero them explicitly.
- YAML embedded in a Terraform heredoc: a double-quoted YAML string processes `\`-escapes (so
  `"trace_id=(\w+)"` is invalid YAML — `\w` isn't a recognized escape), while the *Terraform*
  heredoc itself does not touch backslashes at all. Use single-quoted YAML strings for anything
  with a literal backslash.

## ADRs

`adr/ADR-PL-*.md` — decisions owned by this repo (what it provisions, its boundary against
`papeete-deploy`/`papeete-actor`). Copy `adr/template.md` for a new one; link the canonical
implementation rather than restating it in the ADR.
