# `ingress-nginx-local`

The worked example: `modules/ingress-nginx` applied to Docker Desktop's Kubernetes, the same
target `papeete-deploy`'s own k8s examples use.

```bash
kubectl config use-context docker-desktop   # or pass -var kube_context=<yours>
terraform init
terraform apply
kubectl -n ingress-nginx get pods           # controller coming up
terraform destroy
```
