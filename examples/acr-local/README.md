# `acr-local`

The worked example: `modules/acr` applied to a throwaway resource group, plus the two things a
local Docker Desktop cluster needs before it can run what the registry holds — a read-only pull
Secret, and one containerd `hosts.toml` on the node.

"local" names the *environment* this registry serves — a developer's Docker Desktop cluster — not
where it runs. A registry is an Azure resource, and it is reachable from the cluster precisely
because it is not in it.

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform apply -var registry_name=<globally-unique-name>
```

That creates the registry and its two tokens, writes a `kubernetes.io/dockerconfigjson` Secret
named `acr-pull` into each of `var.pull_secret_namespaces`, and writes the node file described
below. Anything running an image from this registry then just references the Secret:

```yaml
spec:
  imagePullSecrets:
    - name: acr-pull
```

The push credentials are outputs rather than anything written to disk — read them at the moment
you need them, e.g. to point [`../buildkit-local`](../buildkit-local/) at this registry:

```bash
terraform output -raw login_server
terraform output -raw push_password | docker login "$(terraform output -raw login_server)" \
  --username "$(terraform output -raw push_username)" --password-stdin

terraform destroy
```

Requires the **Premium** SKU (the module's default): scope maps and tokens exist only there.

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
it out of the mirror's path. Measured on a cold image, no host copy, least-privilege token:

| | Result |
|---|---|
| No bypass | indefinite `ImagePullBackOff` |
| Host logged in with a scope-mapped token | indefinite `ImagePullBackOff` |
| Host logged in with the **admin** account | pulls, sometimes, after retries |
| **Bypass, host logged out, admin disabled** | **11–13s, deterministic, zero failures** |

The admin account is therefore *not* needed, and `modules/acr` leaves it off. The bypass names a
stable public hostname — no pinned ClusterIP, no `hostAliases`, no privileged DaemonSet — but it
does not survive a cluster recreate, which is why it is applied here rather than assumed.

**None of this applies to a real cluster.** AKS, EKS, GKE and plain kind have no `_default` mirror;
there, the pull Secret alone is the whole story. Set `node_registry_bypass = false` there.
