# `ingress-nginx`

Installs [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) into an existing cluster via
the `helm` Terraform provider. One release, one namespace, shared by every actor/product deployed
to that cluster afterwards — nothing here is specific to any one actor or product
([ADR-PL-0001](../../adr/ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md)).

This module does not configure a `kubernetes`/`helm` provider itself — the caller (a root module,
or one of this repo's own `examples/`) supplies it, pointed at whichever cluster/context should
receive the controller. That keeps this module reusable across environments without an opinion
baked in about which one.

## Use directly

```hcl
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}

module "ingress" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/ingress-nginx?ref=v0.1.0"
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `namespace` | Namespace the controller is installed into | `"ingress-nginx"` |
| `create_namespace` | Create `namespace` if missing | `true` |
| `chart_version` | Chart version to pin | `null` (latest resolved by Helm) |
| `set_values` | Helm `--set`-style overrides, as a map | `{}` |
| `values_yaml` | A full `values.yaml` document as a string | `null` |

## Outputs

| Name | Description |
|---|---|
| `namespace` | Namespace the release landed in |
| `release_name` | Helm release name |
| `chart_version` | Chart version actually installed |

## What every actor's overlay needs to know

Nothing beyond the chart's own default ingress class, `nginx` — an actor's
[`deploy/k8s/overlays/<recipe>`](https://github.com/papeete-hub/papeete-actor) sets
`spec.ingressClassName: nginx` on its own `Ingress` resource (if it has one) to route through the
controller this module installs. This module never reads or writes anything under an actor's
folder.

## Verified against

Docker Desktop's Kubernetes only, same as `papeete-deploy`'s k8s path. A cluster that isn't
Docker Desktop should still work (this is a plain Helm chart install), just not exercised by this
repo's own tests yet.
