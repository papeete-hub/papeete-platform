# `acr-local`

The worked example: `modules/acr` applied to a throwaway resource group, issuing the push and pull
tokens a local cluster's in-cluster builder uses.

"local" names the *environment* this registry serves — a developer's Docker Desktop cluster — not
where it runs. Unlike this repo's other examples there is no `kube_context`: a registry is an
Azure resource, and it is reachable from the cluster precisely because it is not in it.

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform apply -var registry_name=<globally-unique-name>

terraform output login_server
terraform output -raw push_password | docker login $(terraform output -raw login_server) \
  --username "$(terraform output -raw push_username)" --password-stdin

terraform destroy
```

The push credentials feed the builder's `$DOCKER_CONFIG/config.json`; the pull credentials feed
the `kubernetes.io/dockerconfigjson` Secret every namespace running these images references. Both
are Terraform outputs rather than anything written to disk here — read them with
`terraform output -raw` at the moment you need them.

Requires the **Premium** SKU (the module's default): scope maps and tokens exist only there.
