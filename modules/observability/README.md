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

## Outputs

| Name | Description |
|---|---|
| `namespace` | Namespace the stack landed in |
| `otlp_grpc_endpoint` | `otel-collector.<namespace>.svc.cluster.local:4317` — every actor points `OTEL_EXPORTER_OTLP_ENDPOINT` here |
| `grafana_service_name` | In-cluster service name for Grafana |

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
