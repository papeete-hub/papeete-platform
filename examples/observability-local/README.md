# `observability-local`

The worked example: `modules/observability` applied to Docker Desktop's Kubernetes, the same
target `papeete-deploy`'s own k8s examples use.

```bash
kubectl config use-context docker-desktop   # or pass -var kube_context=<yours>
terraform init
terraform apply
kubectl -n observability get pods                        # everything coming up

kubectl -n observability get secret grafana -o jsonpath="{.data.admin-password}" | base64 -d
# open http://grafana.local — user "admin", password from above

terraform destroy
```

Point actors at `otel-collector.observability.svc.cluster.local:4317` (this example's
`otlp_grpc_endpoint` output) for `OTEL_EXPORTER_OTLP_ENDPOINT`.

## Grafana on `grafana.local`

This example sets `grafana_ingress_host = "grafana.local"` (the `grafana_host` variable), so
Grafana comes up behind an `Ingress` instead of needing a port-forward. It assumes
[`ingress-nginx-local`](../ingress-nginx-local/) is already applied — the `Ingress` is created
either way, but nothing serves it without a controller.

The hostname resolves only once a hosts file says so —
[`modules/ingress-nginx`](../../modules/ingress-nginx/#reaching-the-controller-from-your-machine)
covers which file to edit and the WSL2 trap that silently discards the entry. Until then, or to
check the routing on its own:

```bash
curl -sI -H 'Host: grafana.local' http://127.0.0.1/login    # 200 → routed correctly
```

Prefer the port-forward? Pass `-var grafana_host=null` and no `Ingress` is created at all:

```bash
terraform apply -var grafana_host=null
kubectl -n observability port-forward svc/grafana 3000:80   # then http://localhost:3000
```
