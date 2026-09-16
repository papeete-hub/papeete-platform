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
- Not Kubernetes-exclusive by design, and no longer in theory only: `modules/acr` targets `azurerm`.

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

That prohibition is about `modules/`. An **environment** root module is a different thing and is
allowed: `environments/local-platform/` supplies its own providers, owns its own state, combines
several modules, and exists to be *applied* rather than `source`d — nothing under `modules/`
depends on it. ADR-PL-0003 anticipated exactly this when it put an environment's backend in "the
root module that owns that environment".

Not every module is a Helm install. `modules/acr`, `modules/buildkit`, `modules/rabbitmq` and
`modules/sqlserver` are built from `azurerm_*` / `kubernetes_*` provider resources — none has a
chart worth installing
([ADR-PL-0002](./adr/ADR-PL-0002-image-building-is-shared-platform-infrastructure.md)) — so the
variable shape below applies to the Helm modules and does not generalise to them.

**A shared component is shared; a product gets a tenant on it.** `modules/rabbitmq` is one broker
with a `vhosts` list, `modules/sqlserver` one server with a `databases` list — never one per
product. Both are required inputs with no default, following `modules/acr`'s `repository_patterns`:
that is how a module stays product-agnostic while the caller declares what lives on it. Both
default to namespace `platform`, so the second one installed there needs
`create_namespace = false`.

**A product finds a shared component by name, never by being told.** Each publishes a per-tenant
connection Secret (`platform-<component>-<tenant>`, shaped for `envFrom`), and
`modules/secret-reflector` mirrors it into every namespace matching `reflect_to_namespaces` —
including namespaces created later, which is the per-PR stand-up case a caller-declared list cannot
serve ([ADR-PL-0004](./adr/ADR-PL-0004-platform-credentials-reach-products-by-reflection.md)). A
Secret is namespace-scoped, so without the reflector those Secrets help only a same-namespace pod;
the annotations are inert when it is not installed.

Within a Helm module, every `helm_release` follows the same per-resource variable shape:
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

### `modules/rabbitmq` and `modules/sqlserver`

**Discovered by actually applying these against `docker-desktop`** — none of it is visible from
`terraform validate`:

- **Importing RabbitMQ definitions suppresses the default `/` vhost.** A stock broker has `/` and
  `guest`; one booting with `load_definitions` has only what the document declares —
  `rabbitmqctl list_vhosts` confirms it. A client connecting with no vhost in its URI therefore
  fails, which is what you want on a shared broker.
- **Both import and `CREATE DATABASE` add but never remove.** Dropping a name from `vhosts` or
  `databases` leaves the vhost or database in place, and Terraform reports no difference — the
  declared list is the input, not the server's state. Deleting is a deliberate manual act.
- **`sqlcmd`'s path differs by image.** `mcr.microsoft.com/mssql-tools` has it at
  `/opt/mssql-tools/bin/sqlcmd`; ODBC 18 images (including the server image) use
  `/opt/mssql-tools18/bin/sqlcmd`. There is no `mssql-tools18` repository on MCR — that 404s.
  Hence the `sqlcmd_path` variable; a wrong value fails only at apply.
- **SQL Server's `fs_group` is load-bearing.** The image runs as uid 10001 and cannot create
  `master` on a PVC it may not write, so it exits on startup. RabbitMQ needs the same for uid 999.
- **A Job's pod template is immutable**, so the database-provisioning Job is named after a hash of
  the SQL it runs; that is what makes an added database appear on the next apply rather than
  silently doing nothing.
- **Readiness is not "accepts a login".** SQL Server opens 1433 well before it will authenticate,
  so the Job retries `SELECT 1` rather than trusting the probe — measured at ~5s after ready.
- **Bitnami charts are no longer an option for these.** `docker.io/bitnami/rabbitmq` lists zero
  tags (the free catalogue moved to `bitnamilegacy`), so the chart cannot pull. Check Docker Hub
  before reaching for a Bitnami chart in this repo.
- **Reflection is a copy, and deleting the source deletes every mirror** — so destroying the
  platform empties every consumer namespace. `reflection-auto-enabled` is the annotation that
  makes a namespace created later get a copy; without it a mirror must be requested per consumer.
- **Each `-local` example uses its own namespace**, not the modules' shared `platform` default:
  two examples are two states, so both creating one namespace collides. The shared-namespace
  shape (`create_namespace = false` on the second) lives in the module READMEs.

## ADRs

`adr/ADR-PL-*.md` — decisions owned by this repo (what it provisions, its boundary against
`papeete-deploy`/`papeete-actor`). Copy `adr/template.md` for a new one; link the canonical
implementation rather than restating it in the ADR.
