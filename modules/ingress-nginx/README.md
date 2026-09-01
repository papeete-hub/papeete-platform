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

## Reaching the controller from your machine

The controller answers on whatever address its own Service exposes. Find it, then confirm it is
really the controller answering — a 404 from nginx is the default backend, and is the success
signal here, not a failure:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
curl -sI http://127.0.0.1/          # HTTP/1.1 404 Not Found, served by nginx → reachable
```

On a local cluster that maps host ports 80/443 (Docker Desktop's Kubernetes, or a `kind` cluster
created with `extraPortMappings`), that address is `127.0.0.1` regardless of what `EXTERNAL-IP`
reports — a `kind` controller commonly shows an address on Docker's own bridge network
(`172.18.0.x`) that is *not* routable from the host, while the mapped port on `127.0.0.1` is. Trust
the `curl`, not the `EXTERNAL-IP` column.

### Hostnames, via a hosts file

A hostname on an `Ingress` is inert until something resolves it. Locally that is a hosts-file
entry pointing every name at the controller's address — no DNS server, no wildcard:

```
127.0.0.1   grafana.local
127.0.0.1   k8s.local
```

Which file to edit is decided by **where the browser runs**, not where `kubectl` runs:

- **Browser on Windows, cluster in WSL2** — edit `C:\Windows\System32\drivers\etc\hosts`, as
  Administrator. WSL's own `/etc/hosts` has no effect on a Windows browser.
- **Browser or `curl` inside WSL2** — edit `/etc/hosts`, *and* first add this to `/etc/wsl.conf`:

  ```ini
  [network]
  generateHosts = false
  ```

  Without it WSL regenerates `/etc/hosts` from scratch on every boot and silently discards the
  entries. The file's own header says so; it is easy to add entries, see them work, and find them
  gone the next morning.
- **Linux or macOS** — `/etc/hosts`, no trap.

`.local` is worth one caveat: it is mDNS/Bonjour's reserved suffix, so on a host running Avahi or
macOS a `.local` name may be resolved by multicast before the hosts file is consulted. A hosts
entry normally still wins, but if a name resolves to something unexpected, that is the first thing
to suspect — `.localhost` or `.test` avoid the question entirely.

### One host, many workloads

Platform services get their own name (`grafana.local` — see
[`modules/observability`](../observability/#reaching-grafana) for why a dedicated host beats a
sub-path). Product workloads share one, distinguished by path:

```
http://k8s.local/<product>/<environment>/<actor-local path>
```

That prefix is not something an actor author types. `papeete-deploy` injects it into every
`Ingress` it applies, at apply time, from the product name and target namespace
(`ADR-PD-0005`) — an actor's own overlay authors only its bare local segment (`path: /api`) plus
`host: k8s.local` and `ingressClassName: nginx`, and comes out as
`k8s.local/foundry/foundry-local/api`. The prefix is what lets the same actor deploy into two
namespaces at once without colliding: ingress-nginx's admission webhook enforces host+path
uniqueness cluster-wide, so two instances sharing a host *must* differ in path.

Nothing in this module knows any of those names. It installs a controller; hostnames arrive on
`Ingress` objects owned by whatever is being exposed, and resolving them is the caller's job.

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
