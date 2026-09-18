# `sqlserver`

One [SQL Server](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-overview) instance
for the whole cluster, with **one database per product** on it. A database server is a shared
component: a product gets a database on the shared server, not a server of its own — the same rule
[`rabbitmq`](../rabbitmq/) applies to vhosts.

Nothing here names a product
([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)). The
`databases` list is a required input with no default: what lives on the server is the caller's
declaration.

Built from `kubernetes_*` resources rather than a `helm_release` — Microsoft publishes no Helm
chart, the same "no chart worth installing" case as [`buildkit`](../buildkit/)
([ADR-PL-0002](../../adr/ADR-PL-0002-image-building-is-shared-platform-infrastructure.md)). As with
every module here, the `kubernetes` provider is supplied by the caller — a root module, or
[`examples/sqlserver-local`](../../examples/sqlserver-local/).

## Use directly

```hcl
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

module "sqlserver" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/sqlserver?ref=v0.1.0"

  databases   = ["foundry", "reliever"]
  sa_password = var.sa_password
}
```

A .NET product then takes its own connection string out of the map:

```hcl
# Server=sqlserver.platform.svc.cluster.local,1433;Database=reliever;User Id=sa;...
module.sqlserver.connection_strings["reliever"]
```

Note the **comma** before the port — SQL Server's own syntax, not `host:port`. The `endpoint`
output is already in that form.

## One namespace with the broker

`namespace` defaults to `platform` here and in [`rabbitmq`](../rabbitmq/), so both land in one
shared-services namespace. They are two modules, so exactly one of them may create it — set
`create_namespace = false` on the second. The [rabbitmq README](../rabbitmq/README.md#one-namespace-with-the-database)
has the snippet. The paired examples each use their own namespace instead, so both can be applied
to one cluster without colliding.

## How the databases get there

SQL Server has no equivalent of the definitions file RabbitMQ imports at boot, and its image runs
no init scripts, so creating a database takes a real connection. This module runs a **Kubernetes
Job** that waits for the server to accept a login and then issues one guarded
`IF DB_ID(N'...') IS NULL CREATE DATABASE` per name.

A Job rather than a second Terraform provider aimed at the server, because such a provider would
have to be configured before the server it talks to exists. The Job needs nothing that is not
already in the cluster.

- **The Job's name carries a hash of the script it runs.** A Job's pod template is immutable, so
  adding a database has to produce a differently-named Job rather than an update to this one. That
  hash is what makes the new database appear on the next apply.
- **`wait_for_databases` (default true) blocks the apply until the databases exist**, so a caller
  wiring a product up in the same apply does not race it.
- **The Job waits on a query, not on readiness.** The readiness probe reports the port is open
  well before the server will accept a login; the Job retries `SELECT 1` until it succeeds.
  Measured on `docker-desktop`: the login was accepted 5s after the pod went ready.
- **Creation adds; it never removes.** Dropping a name from `databases` does not drop the
  database — deliberately, since a `DROP DATABASE` triggered by editing a list is not a mistake
  anyone should be one keystroke from. Terraform will not report the difference.

## How a product finds it

Each database gets a **connection Secret** at a well-known name — `platform-sqlserver-<database>` —
shaped for `envFrom`:

```yaml
envFrom:
  - secretRef:
      name: platform-sqlserver-reliever  # SQLSERVER_CONNECTION_STRING, _HOST, _PORT, _DATABASE, _USERNAME, _PASSWORD
```

A Secret is namespace-scoped, so by default that only helps a pod in this namespace. Set
`reflect_to_namespaces` to a regex and the Secret is annotated for
[`modules/secret-reflector`](../secret-reflector/), which mirrors it into every matching namespace
**including ones created later** — the per-PR stand-up case a list of namespaces cannot serve
([ADR-PL-0004](../../adr/ADR-PL-0004-platform-credentials-reach-products-by-reflection.md)). The
annotations are inert if no reflector is installed.

## Licensing

`edition` sets `MSSQL_PID` and defaults to **`Developer`**: full-featured, free, and licensed for
**development and test only**. A shared environment serving anything real needs `Express` (free,
capped at 10GB per database) or a paid edition. This is a licensing decision, so it has no silent
production default — change it deliberately.

`ACCEPT_EULA=Y` is set in `main.tf` rather than hidden in a values file, so that accepting it is a
visible act.

## Credentials

One `sa` login, from the required `sa_password`, validated against SQL Server's own complexity
policy at plan time — otherwise the server exits on first boot with a message visible only in the
pod log.

**Remains to realize: per-database logins.** Every product currently connects as `sa`, so the
database is a namespace rather than a boundary. A login per database needs a credential per
product to be stored and handed out, which is a decision about how products receive secrets, not
about this module.

## Notes

- **A StatefulSet with a PVC at `/var/opt/mssql`**, holding the system databases, every product's
  database, and the logs.
- **`fs_group` is load-bearing.** The image runs as uid 10001; without a matching `fs_group` the
  PVC is not writable by it and the server exits on startup unable to create `master`.
- **SQL Server will not start below 2GiB of memory.** The example states that floor as a request
  rather than leaving it to be discovered.
- **`sqlcmd`'s path moved between tool generations**, so it is a variable. The default
  `tools_image` (`mcr.microsoft.com/mssql-tools`) ships it at `/opt/mssql-tools/bin/sqlcmd`, while
  ODBC 18 images use `/opt/mssql-tools18/bin/sqlcmd` — verified by running both, since a wrong
  path fails only at apply. Set `sqlcmd_path` whenever `tools_image` changes. (The server image
  itself carries the 18 path, but is ~1.5GB to pull for one query.)
- **`-C` on every `sqlcmd` call** trusts the server's self-signed certificate, which is the only
  kind it has here. The generated connection strings say `TrustServerCertificate=True` for the
  same reason.

## Azure later

This is the in-cluster variant, which is what a local cluster and a shared dev environment want.
A cloud-managed variant (`azurerm_mssql_server` + `azurerm_mssql_database`) is the expected next
step for anything beyond that, and would be a sibling module rather than a flag here — the inputs
barely overlap once there is no pod, no PVC and no `sa`. ADR-PL-0002 anticipated exactly this shape
of split when [`acr`](../acr/) arrived.

## Inputs

| Name | Type | Default | Notes |
|------|------|---------|-------|
| `databases` | `list(string)` | — | **Required.** One per product. Name charset is validated. |
| `sa_password` | `string` | — | **Required**, sensitive, complexity-checked. |
| `namespace` | `string` | `platform` | Shared with `rabbitmq`. |
| `create_namespace` | `bool` | `true` | False when something else made it. |
| `name` | `string` | `sqlserver` | Also the in-cluster hostname. |
| `image` | `string` | `mcr.microsoft.com/mssql/server:2025-latest` | |
| `tools_image` | `string` | `mcr.microsoft.com/mssql-tools:latest` | Supplies `sqlcmd` to the Job. |
| `sqlcmd_path` | `string` | `/opt/mssql-tools/bin/sqlcmd` | Must match `tools_image`. |
| `edition` | `string` | `Developer` | Licensing — see above. |
| `port` | `number` | `1433` | |
| `storage_size` | `string` | `20Gi` | |
| `storage_class_name` | `string` | `null` | Null uses the cluster default. |
| `wait_for_databases` | `bool` | `true` | Block the apply until they exist. |
| `provisioning_timeout` | `string` | `10m` | Terraform-side. |
| `provisioning_timeout_seconds` | `number` | `300` | Job-side; keep below the above. |
| `extra_env` | `map(string)` | `{}` | e.g. `MSSQL_COLLATION`. |
| `resources` | `object` | `null` | Needs ≥2GiB to start. |
| `connection_secret_prefix` | `string` | `platform-sqlserver` | Well-known name products reference. |
| `reflect_to_namespaces` | `string` | `null` | Regex; null publishes nothing beyond this namespace. |

## Outputs

`namespace`, `service_name`, `host`, `port`, `endpoint`, `databases`, `connection_strings`
(sensitive, keyed by database), `sa_secret_name`, `connection_secret_names` (keyed by database).

Connect locally:

```bash
kubectl -n platform port-forward svc/sqlserver 1433
```
