# papeete-platform

Terraform modules for infrastructure **shared across actors and products** — installed once per
cluster/environment, owned by no single one of them. Split out on purpose: neither
[`papeete-deploy`](https://github.com/papeete-hub/papeete-deploy) (deploys one product's declared
actors into an environment that's assumed to already have what it needs) nor
[`papeete-actor`'s `deploy/terraform/`](https://github.com/papeete-hub/papeete-actor) (an
individual actor's own infra) is the right owner for something like a cluster's ingress controller
or a broker every actor talks to. See
[ADR-PL-0001](./adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md).

```
modules/
  ingress-nginx/     installs an ingress controller into an existing k8s cluster
examples/
  ingress-nginx-local/   the worked example, against Docker Desktop's Kubernetes
```

Each module under `modules/` is a complete, independently deployable root module — no wrapper, no
umbrella stack. Not Kubernetes-exclusive: a future module can target any provider its component
needs (a cloud DNS zone, a managed queue), not only `kubernetes`/`helm`.

## Use a module

```hcl
module "ingress" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/ingress-nginx?ref=v0.1.0"
}
```

Or apply it directly — see [`examples/ingress-nginx-local`](./examples/ingress-nginx-local/):

```bash
cd examples/ingress-nginx-local
terraform init
terraform apply
```

## What's here today

Only [`modules/ingress-nginx`](./modules/ingress-nginx/) — an ingress controller, the one shared
piece of infra multiple actors in a cluster consistently need. Nothing else ships speculatively
ahead of a concrete need (ADR-PL-0001's Consequences).

## Boundary

- **A module here never takes an actor or product identity as input.** If a variable would only
  ever be set to one actor's name, that infra belongs in that actor's own `deploy/terraform/`
  instead (`papeete-actor`'s `ADR-PA-0025`), not here.
- **This repo provisions; `papeete-deploy` consumes.** `papeete-deploy` still assumes an
  environment's shared infra (an ingress class, a broker) already exists — it never calls into this
  repo, and this repo never reads a `product.yaml`.

## Releasing

Modules are consumed by git ref, Terraform's own registry-free convention — no package index, no
publish step:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Licence

MIT.
