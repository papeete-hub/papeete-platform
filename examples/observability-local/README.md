# `observability-local`

The worked example: `modules/observability` applied to Docker Desktop's Kubernetes, the same
target `papeete-deploy`'s own k8s examples use.

```bash
kubectl config use-context docker-desktop   # or pass -var kube_context=<yours>
terraform init
terraform apply
kubectl -n observability get pods                        # everything coming up

# Grafana, pre-wired with Prometheus/Loki/Tempo datasources and trace-to-logs correlation:
kubectl -n observability port-forward svc/grafana 3000:80
kubectl -n observability get secret grafana -o jsonpath="{.data.admin-password}" | base64 -d
# open http://localhost:3000 — user "admin", password from above

terraform destroy
```

Point actors at `otel-collector.observability.svc.cluster.local:4317` (this example's
`otlp_grpc_endpoint` output) for `OTEL_EXPORTER_OTLP_ENDPOINT`.
