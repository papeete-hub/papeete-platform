# `local-platform`

The shared services every product on a local `docker-desktop` cluster uses, applied **once** and
meant to stay: one RabbitMQ, one SQL Server, and the reflector that carries their credentials into
product namespaces.

This is the answer to *"where do I find the connection details?"* — you don't. A product's pod
names a Secret and the platform puts it there.

```bash
cd environments/local-platform
kubectl config use-context docker-desktop
terraform init
terraform apply
```

## Not an example, and not an umbrella module

- **`examples/<name>-local`** demonstrates one module and is disposable — apply, look, destroy
  ([ADR-PL-0003](../../adr/ADR-PL-0003-example-state-is-local-shared-environments-get-a-remote-backend.md)).
- **This** is a root module that owns an environment: it supplies its own providers, holds its own
  state, and is meant to outlive any product deployed against it.
- It is **not** an umbrella module under `modules/`. That prohibition is unchanged — nothing here
  is `source`-able, and no module depends on this directory.

## Onboarding a product

Add a name to `tenants`. That is the whole act:

```hcl
tenants = ["foundry", "reliever", "the-new-one"]
```

`terraform apply` then creates a vhost on the broker, a database on the server, and the two
connection Secrets for it — which the reflector mirrors into every namespace matching
`consumer_namespaces`.

## What a product's pod writes

Nothing about this environment. Just the well-known names:

```yaml
envFrom:
  - secretRef:
      name: platform-sqlserver-reliever  # SQLSERVER_CONNECTION_STRING, _HOST, _PORT, _DATABASE, ...
  - secretRef:
      name: platform-rabbitmq-reliever   # RABBITMQ_URI, _HOST, _PORT, _VHOST, ...
```

Those Secrets appear in a namespace **as it is created**, so a per-PR stand-up needs no re-apply
([ADR-PL-0004](../../adr/ADR-PL-0004-platform-credentials-reach-products-by-reflection.md)).
Verified: a namespace created after this environment was applied had all four Secrets within
seconds, and a pod there reached the database through `envFrom` alone.

## Inputs worth setting

| Name | Default | Notes |
|------|---------|-------|
| `tenants` | `["foundry", "reliever"]` | One name per product. Adding one onboards it. |
| `consumer_namespaces` | `.*` | Regex of namespaces the credentials are mirrored into. |
| `namespace` | `platform` | Holds the shared services. |
| `kube_context` | `docker-desktop` | |
| `rabbitmq_admin_password` | local dev value | Defaulted because this is a local cluster. |
| `sa_password` | local dev value | Same. |

**`consumer_namespaces = ".*"` means every namespace in the cluster can read every tenant's
credential.** That is acceptable here, where the cluster is one person's laptop and every namespace
is theirs. It is not acceptable in a shared environment, which should narrow the regex — and should
first have the per-tenant logins that ADR-PL-0004 lists as remaining to realize, since today every
tenant's Secret carries the same `admin`/`sa` login.

## Going away

```bash
terraform destroy
```

Deleting the source Secrets deletes every mirror, so this also empties the consumer namespaces —
intended, and worth knowing before running it while something is using the platform.
