# `rabbitmq`

One [RabbitMQ](https://www.rabbitmq.com/) broker for the whole cluster, with **one vhost per
product** on it. Messaging is a shared component: a product gets a vhost on the shared broker, not
a broker of its own — the same rule [`sqlserver`](../sqlserver/) applies to databases.

Nothing here names a product
([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)). The
`vhosts` list is a required input with no default, exactly as
[`modules/acr`](../acr/)'s `repository_patterns` is: what lives on the broker is the caller's
declaration.

Built from `kubernetes_*` resources rather than a `helm_release` — see
[Why not a chart](#why-not-a-chart). As with every module here, the `kubernetes` provider is
supplied by the caller — a root module, or
[`examples/rabbitmq-local`](../../examples/rabbitmq-local/).

## Use directly

```hcl
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

module "rabbitmq" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/rabbitmq?ref=v0.1.0"

  vhosts         = ["foundry", "reliever"]
  admin_password = var.rabbitmq_admin_password
}
```

A product then takes its own URI out of the `amqp_uris` map:

```hcl
# amqp://admin:...@rabbitmq.platform.svc.cluster.local:5672/reliever
module.rabbitmq.amqp_uris["reliever"]
```

## One namespace with the database

`namespace` defaults to `platform` here and in [`sqlserver`](../sqlserver/), so both land in one
shared-services namespace. They are two modules, so exactly one of them may create it:

```hcl
module "rabbitmq" {
  source = "../../modules/rabbitmq"
  vhosts = ["foundry", "reliever"]
  admin_password = var.rabbitmq_admin_password
  # creates the namespace
}

module "sqlserver" {
  source           = "../../modules/sqlserver"
  databases        = ["foundry", "reliever"]
  sa_password      = var.sa_password
  create_namespace = false # rabbitmq already made it
}
```

The paired examples each use their own namespace instead, so both can be applied to one cluster
without colliding.

## How the vhosts get there

The caller's list is rendered into a **definitions document** — a Secret mounted at
`/etc/rabbitmq/definitions/definitions.json` — and `rabbitmq.conf` points `load_definitions` at
it. The broker imports it at boot, so vhosts exist before anything can connect.

This is what lets a single `terraform apply` produce a fully provisioned broker with no second
provider aimed at the running server, and no post-apply step. The pod template carries a hash of
the definitions, so changing `vhosts` rolls the broker and re-imports.

Two consequences worth knowing:

- **Importing definitions suppresses the default `/` vhost.** A stock RabbitMQ has `/` and a
  `guest` user; this one has neither unless `/` is in `vhosts`. Verified on `docker-desktop` —
  `rabbitmqctl list_vhosts` returns only the declared names. Anything connecting with no vhost in
  its URI will fail, which is the intended outcome for a broker shared by several products.
- **Import adds; it never removes.** Dropping a name from `vhosts` rolls the broker but leaves the
  vhost, its queues and its messages in place. Deleting one is a deliberate act:
  `rabbitmqctl delete_vhost <name>`. Terraform will not report the difference, because the
  definitions document is the input, not the broker's state.

## Credentials

One administrator user, with full permissions on every declared vhost, from the required
`admin_password`. The definitions importer accepts a clear-text `password` in place of a hash,
which is why the document is a Secret rather than a ConfigMap.

**Remains to realize: per-vhost users.** Every product currently connects as the same
administrator, so the vhost is a namespace rather than a boundary. Generating a user per vhost
needs a credential per product to be stored and handed out, which is a decision about how products
receive secrets, not about this module.

## Why not a chart

- **Bitnami's `rabbitmq` chart cannot pull.** Bitnami moved its free catalogue to a
  `bitnamilegacy` repository; `docker.io/bitnami/rabbitmq` now lists **zero tags**, and the chart
  itself was last published in August 2025. Checked before choosing, not assumed.
- **The official RabbitMQ Cluster Operator was the real alternative**, and is healthy
  (`v2.23.0`, released days before this module was written). It was rejected for now on a
  Terraform-shaped cost: the broker and its vhosts would be custom resources, and
  `kubernetes_manifest` resolves a CRD's schema at **plan** time — so the operator and the
  resources it defines cannot be created in one `terraform apply`. Two operators
  (cluster + messaging-topology) and a split apply is a lot of machinery for one shared broker.
  It is the right answer the moment this needs to be an actual cluster with HA, and that is when
  to revisit.
- The official `rabbitmq` image, by contrast, is a Docker Official Image rebuilt continuously, and
  a single-node broker is a StatefulSet, a Service and two mounted documents.

## Notes

- **A StatefulSet, not a Deployment.** Mnesia keys its data directory by node name and the node
  name is the pod's hostname; a Deployment would rename the broker on every roll and orphan what
  it had just written.
- **One replica, deliberately.** Clustering needs peer discovery and a shared Erlang cookie —
  which is the cluster operator's job, above.
- Readiness uses `rabbitmq-diagnostics check_port_connectivity`, liveness `status`; the latter is
  slower and is given a longer initial delay so a booting broker importing definitions is not
  killed underneath itself.

## Inputs

| Name | Type | Default | Notes |
|------|------|---------|-------|
| `vhosts` | `list(string)` | — | **Required.** One per product. |
| `admin_password` | `string` | — | **Required**, sensitive, min 8 chars. |
| `namespace` | `string` | `platform` | Shared with `sqlserver`. |
| `create_namespace` | `bool` | `true` | False when something else made it. |
| `name` | `string` | `rabbitmq` | Also the in-cluster hostname. |
| `image` | `string` | `rabbitmq:4-management` | A `-management` variant exposes the HTTP API. |
| `admin_username` | `string` | `admin` | |
| `amqp_port` | `number` | `5672` | |
| `management_port` | `number` | `15672` | |
| `storage_size` | `string` | `8Gi` | |
| `storage_class_name` | `string` | `null` | Null uses the cluster default. |
| `extra_config` | `string` | `""` | Appended to `rabbitmq.conf`. |
| `resources` | `object` | `null` | Unconstrained by default. |

## Outputs

`namespace`, `service_name`, `host`, `amqp_port`, `amqp_endpoint`, `amqp_uris` (sensitive, keyed by
vhost), `vhosts`, `management_url`.

Reach the management UI locally:

```bash
kubectl -n platform port-forward svc/rabbitmq 15672
```
