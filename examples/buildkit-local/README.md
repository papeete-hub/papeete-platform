# `buildkit-local`

The worked example: `modules/buildkit` applied to Docker Desktop's Kubernetes, wired to push to
the registry [`examples/acr-local`](../acr-local/) creates.

```bash
kubectl config use-context docker-desktop   # or pass -var kube_context=<yours>
terraform init
terraform apply \
  -var registry_server="$(terraform -chdir=../acr-local output -raw login_server)" \
  -var registry_username="$(terraform -chdir=../acr-local output -raw push_username)" \
  -var registry_password="$(terraform -chdir=../acr-local output -raw push_password)"

kubectl -n buildkit get pods                # buildkitd Running, and unprivileged
terraform output buildkit_addr              # what a client sets BUILDKIT_HOST to
```

Prove it can build and push before anything depends on it:

```bash
kubectl -n buildkit exec deploy/buildkitd -- sh -c '
  mkdir -p /tmp/ctx && printf "FROM busybox:1.36\nRUN echo ok > /probe.txt\n" > /tmp/ctx/Dockerfile &&
  buildctl --addr unix:///run/user/1000/buildkit/buildkitd.sock build --frontend dockerfile.v0 \
    --local context=/tmp/ctx --local dockerfile=/tmp/ctx \
    --output type=image,name=<login-server>/<repo>/probe:v1,push=true'
```

```bash
terraform destroy
```

Omit the three `registry_*` variables for a builder with no credentials — it still builds, it just
has nowhere to publish to.
