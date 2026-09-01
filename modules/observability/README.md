# `observability`

Installs an OpenTelemetry-shaped observability stack into an existing cluster via the `helm`
Terraform provider: an OTel Collector receiving traces/logs/metrics over OTLP gRPC, Tempo for
traces, Loki for logs, Prometheus for metrics, and Grafana pre-wired with all three as
datasources, trace-to-logs correlation included. One release per component, shared by every
actor/product deployed to that cluster afterwards — nothing here is specific to any one actor or
product ([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)).

This module does not configure a `kubernetes`/`helm` provider itself — the caller (a root module,
or one of this repo's own `examples/`) supplies it, pointed at whichever cluster/context should
receive the stack.

No Kibana/Elasticsearch by default: logs arrive via OTLP push through the Collector into Loki, so
no Promtail/Fluent-bit sidecar is needed either. Elasticsearch + Kibana are available as a second,
opt-in log store (`var.enable_elasticsearch_kibana = true`) — a genuinely different store from
Loki, not a replacement for it, and off by default.

## Use directly

```hcl
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}

module "observability" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/observability?ref=v0.1.0"
}
```

## Inputs

Shared:

| Name | Description | Default |
|---|---|---|
| `namespace` | Namespace every component is installed into | `"observability"` |
| `create_namespace` | Create `namespace` if missing | `true` |

Per component (`<component>` is one of `otel_collector`, `prometheus`, `loki`, `tempo`,
`grafana`, `elasticsearch`, `kibana`):

| Name | Description | Default |
|---|---|---|
| `enable_<component>` | Install this component (elasticsearch/kibana share one flag, `enable_elasticsearch_kibana`) | `true` (`false` for elasticsearch/kibana) |
| `<component>_chart_version` | Chart version to pin | `null` (latest resolved by Helm) |
| `<component>_set_values` | Helm `--set`-style overrides, as a map | `{}` |
| `<component>_values_yaml` | A full `values.yaml` document, layered on top of this module's own opinionated default for that component | `null` (default used as-is) |

Grafana only — reaching the UI without a port-forward:

| Name | Description | Default |
|---|---|---|
| `grafana_ingress_host` | Hostname to expose Grafana on. Doubles as the on/off switch: `null` creates no `Ingress` at all | `null` |
| `grafana_ingress_class_name` | Ingress class to route through. Only read when `grafana_ingress_host` is set | `"nginx"` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Namespace the stack landed in |
| `otlp_grpc_endpoint` | `otel-collector.<namespace>.svc.cluster.local:4317` — every actor points `OTEL_EXPORTER_OTLP_ENDPOINT` here |
| `grafana_service_name` | In-cluster service name for Grafana |
| `grafana_url` | `http://<grafana_ingress_host>`, or `null` when no Ingress was asked for |

## Reaching Grafana

Unset, `grafana_ingress_host` leaves Grafana on a `ClusterIP` Service with no `Ingress` — the only
way in is a port-forward, which dies with the terminal that started it:

```bash
kubectl -n observability port-forward svc/grafana 3000:80
```

Set it, and Grafana gets an `Ingress` on that hostname routed through
[`modules/ingress-nginx`](../ingress-nginx/)'s class:

```hcl
module "observability" {
  source = "../../modules/observability"

  grafana_ingress_host = "grafana.local"
}
```

**A dedicated hostname, not a sub-path of a shared one.** `grafana.local` rather than
`k8s.local/grafana` is a deliberate choice, not a stylistic one: served under a sub-path Grafana
additionally needs `grafana.ini`'s `server.root_url` and `server.serve_from_sub_path` set, and it
still emits absolute redirects and asset URLs that an ingress rewrite annotation then has to catch.
Its own hostname needs none of that, which is why the `ingress` block this module layers in is
four lines and carries no annotations.

**Making the name resolve is the caller's job.** Nothing in this module writes DNS or a hosts
file — Terraform creates the `Ingress`, and the hostname is inert until something resolves it to
the ingress controller. Locally that means a hosts-file entry pointing at the controller's
address; see [`modules/ingress-nginx`](../ingress-nginx/#reaching-the-controller-from-your-machine)
for how to find that address and which hosts file to edit (there is a WSL2 trap). The Ingress
itself can be verified without touching any of that, by supplying the name as a header:

```bash
curl -sI -H 'Host: grafana.local' http://<controller address>/login    # 200 once routed
```

Grafana's admin password is generated into a Secret by the chart either way:

```bash
kubectl -n observability get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

## What every actor's overlay needs to know

An actor wired with `papeete-observability`'s `configure()` (see that repo) reads its endpoint
from the standard OTel env vars. Point them at this module's output:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: customer   # / waiter / whichever actor
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://otel-collector.observability.svc.cluster.local:4317
```

This module never reads or writes anything under an actor's folder.

## Verified against

Docker Desktop's Kubernetes only, same as `papeete-deploy`'s k8s path and this repo's own
`ingress-nginx` module. A cluster that isn't Docker Desktop should still work (this is a plain set
of Helm chart installs), just not exercised by this repo's own tests yet.

The per-component default `values_yaml` documents above (Collector pipeline wiring, Prometheus
scrape config, Loki single-binary config, Grafana datasource provisioning) are a validated
starting point, not exhaustively tuned — override via `<component>_values_yaml` or
`<component>_set_values` as real usage surfaces gaps.
