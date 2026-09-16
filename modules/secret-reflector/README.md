# `secret-reflector`

Installs [emberstack/kubernetes-reflector](https://github.com/emberstack/kubernetes-reflector), a
controller that mirrors an annotated Secret or ConfigMap into other namespaces — **including
namespaces created after the source was applied**.

That last clause is the entire reason this module exists. A Kubernetes Secret is namespace-scoped,
so a shared component's credential cannot be read by a pod anywhere else; and this ecosystem stands
products up in namespaces that do not exist when the platform is applied (per-PR and per-branch
stand-ups, which
[ADR-PL-0002](../../adr/ADR-PL-0002-image-building-is-shared-platform-infrastructure.md) went to
some trouble to make possible). A list of namespaces supplied at apply time is therefore already
out of date. See
[ADR-PL-0004](../../adr/ADR-PL-0004-platform-credentials-reach-products-by-reflection.md).

A `helm_release`, so it takes this repo's usual `chart_version` / `set_values` / `values_yaml`
trio. As with every module here, the `helm` provider is supplied by the caller — a root module,
[`environments/local-platform`](../../environments/local-platform/), or
[`examples/secret-reflector-local`](../../examples/secret-reflector-local/).

## Use directly

```hcl
module "secret_reflector" {
  source = "git::https://github.com/papeete-hub/papeete-platform.git//modules/secret-reflector?ref=v0.1.0"
}
```

It does nothing visible on its own. It acts on Secrets elsewhere that carry its annotations.

## What a source Secret has to say

```
reflector.v1.k8s.emberstack.com/reflection-allowed:            "true"
reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces: "<regex>"
reflector.v1.k8s.emberstack.com/reflection-auto-enabled:       "true"
reflector.v1.k8s.emberstack.com/reflection-auto-namespaces:    "<regex>"
```

`reflection-auto-enabled` is the load-bearing one: without it a mirror has to be *requested* by
each consumer, which puts the work back on whoever creates the namespace. With it, the controller
pushes a copy into every matching namespace as that namespace appears.

[`modules/rabbitmq`](../rabbitmq/) and [`modules/sqlserver`](../sqlserver/) write these annotations
for you — set their `reflect_to_namespaces` and they do the rest. `annotation_prefix` is an output
here so the convention is stated in one place rather than retyped.

## Verified

On `docker-desktop`, with `environments/local-platform` applied and
`consumer_namespaces = ".*"`: creating a namespace `reliever-pr-42` that did not exist at apply
time produced all four connection Secrets in it within seconds, with **no re-apply**. A pod in that
namespace then reached the database using `envFrom` alone — no credential written into its own
manifest.

## Notes

- **Cluster-wide by design.** The controller watches every namespace whatever namespace it runs
  in, which is why it gets its own (`secret-reflector`) rather than sharing `platform`.
- **A mirror is a copy, not a reference.** Rotating a source credential updates the mirrors, but a
  pod that already read its environment keeps the old value until it restarts.
- **Deleting the source deletes the mirrors.** That is the intended behaviour and it is also a
  foot-gun: a `terraform destroy` of the platform empties every consumer namespace's copy.
- **The regex is trust.** Every namespace matching it can read the credential. `.*` is right for a
  local cluster where every namespace is yours; a shared environment should narrow it to the
  pattern its product namespaces actually follow.

## Inputs

| Name | Type | Default | Notes |
|------|------|---------|-------|
| `namespace` | `string` | `secret-reflector` | Watches the cluster regardless. |
| `create_namespace` | `bool` | `true` | |
| `release_name` | `string` | `reflector` | |
| `chart_version` | `string` | `null` | Unpinned resolves latest — pin beyond local use. |
| `set_values` | `map(string)` | `{}` | |
| `values_yaml` | `string` | `null` | |

## Outputs

`namespace`, `release_name`, `annotation_prefix`.
