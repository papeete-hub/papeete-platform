# `acr-local`

The worked example: `modules/acr` applied to a throwaway resource group, plus the two things a
local Docker Desktop cluster needs before it can run what the registry holds — a pull Secret, and
one containerd `hosts.toml` on the node.

"local" names the *environment* this registry serves — a developer's Docker Desktop cluster — not
where it runs. A registry is an Azure resource, and it is reachable from the cluster precisely
because it is not in it.

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform apply -var registry_name=<globally-unique-name>
```

That creates the registry, writes a `kubernetes.io/dockerconfigjson` Secret named `acr-pull` into
each of `var.pull_secret_namespaces`, and writes the node file described below. Anything running an
image from this registry then just references the Secret:

```yaml
spec:
  imagePullSecrets:
    - name: acr-pull
```

The credential is an output rather than anything written to disk — read it at the moment you need
it, e.g. to point [`../buildkit-local`](../buildkit-local/) at this registry:

```bash
terraform output -raw login_server
terraform output -raw password | docker login "$(terraform output -raw login_server)" \
  --username "$(terraform output -raw username)" --password-stdin

terraform destroy
```

Runs on the **Basic** SKU with the registry's admin account, which is one registry-wide credential
that can both push and pull — the `acr-pull` Secret above can therefore overwrite any tag.
[ADR-PL-0006](../../adr/ADR-PL-0006-the-registry-runs-on-basic-with-its-admin-account.md) records
why that trade was made and what it replaced.

## Moving an existing Premium registry down

One `terraform apply` expresses the whole move — it plans **2 changes and 6 destroys**: the two
tokens, their two passwords and their two scope maps go, the registry goes `Premium -> Basic` and
`admin_enabled false -> true` in place, and the `acr-pull` Secret is rewritten with the admin
credential.

Azure's documented downgrade blockers are geo-replications and connected registries, neither of
which this registry has; tokens and scope maps are Premium-only but are not named as blockers, and
Terraform destroys them before it touches the registry they depend on. So the single apply is
expected to work. If Azure rejects the SKU change anyway, split it — clear the Premium-only
resources first, then let the rest follow:

```bash
terraform apply -target=module.acr.azurerm_container_registry_token.push \
                -target=module.acr.azurerm_container_registry_token.pull \
                -target=module.acr.azurerm_container_registry_scope_map.push \
                -target=module.acr.azurerm_container_registry_scope_map.pull
terraform apply
```

Either way, **everything holding the old push token stops working the moment it is destroyed** —
the builder's `config.json` and the `ACR_PUSH_USERNAME` / `ACR_PUSH_PASSWORD` secrets in the actor
repos. Have `terraform output -raw password` ready to reset them. Running Pods keep the images they
have already pulled; the next pull is what fails.

## The node file, and why it is not optional

Docker Desktop's kind-based node ships `/etc/containerd/certs.d/_default/hosts.toml`, pointing
every registry lookup — every registry, not just Docker Hub — at `kind-registry-mirror` first.
That mirror mounts the host's containerd socket and nothing else, so it serves from the host's
image store and, on a miss, fetches upstream itself. Against a private registry that fails twice
over:

1. It has no credential store, so unless the *host* is logged in it cannot authenticate at all,
   and logs `private registry ... requires authentication`.
2. Even logged in, it breaks on ACR specifically: ACR redirects blob fetches to Azure Blob
   Storage, and the mirror forwards the ACR bearer token across that redirect. Storage rejects it
   with `InvalidAuthenticationInfo`, and the node sees an empty body — reported as
   `short read: expected N bytes but got 0: unexpected EOF`, which containerd does **not** treat
   as a fallback-worthy error.

So `terraform_data.node_registry_bypass` writes one `hosts.toml` naming this registry, which takes
it out of the mirror's path. Measured on a cold image with no host copy, when the registry was
still Premium and the pull credential was a scope-mapped token:

| | Result |
|---|---|
| No bypass | indefinite `ImagePullBackOff` |
| Host logged in with a scope-mapped token (as it then was) | indefinite `ImagePullBackOff` |
| Host logged in with the **admin** account | pulls, sometimes, after retries |
| **Bypass, host logged out** | **11–13s, deterministic, zero failures** |

The finding is about the *bypass*, not about which credential is used, so the bottom row holds just
as well now that the admin account is the credential: the bypass is what takes the mirror out of
the path. The bypass names a stable public hostname — no pinned ClusterIP, no `hostAliases`, no
privileged DaemonSet — but it does not survive a cluster recreate, which is why it is applied here
rather than assumed.

**None of this applies to a real cluster.** AKS, EKS, GKE and plain kind have no `_default` mirror;
there, the pull Secret alone is the whole story. Set `node_registry_bypass = false` there.
