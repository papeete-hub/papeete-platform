# Decision log (`ADR-PL-*`)

Decisions owned by **this repo**: what shared, cross-actor/cross-product infrastructure this repo
provisions, and this repo's own boundary against `papeete-deploy` and `papeete-actor`'s
`deploy/terraform/`.

## The log

| ID | Title | Status |
|----|-------|--------|
| [ADR-PL-0001](./ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md) | papeete-platform is a standalone Terraform repo for infra shared across actors and products | Accepted |
| [ADR-PL-0002](./ADR-PL-0002-image-building-is-shared-platform-infrastructure.md) | Image building is shared platform infrastructure: in-cluster rootless BuildKit pushing to a cloud registry | Accepted |
| [ADR-PL-0003](./ADR-PL-0003-example-state-is-local-shared-environments-get-a-remote-backend.md) | Example state is local and never shared; a shared environment gets a remote backend when there is one | Accepted |
| [ADR-PL-0004](./ADR-PL-0004-platform-credentials-reach-products-by-reflection.md) | A shared component publishes a connection Secret, and reflection carries it into product namespaces | Accepted |
| [ADR-PL-0005](./ADR-PL-0005-the-python-index-is-a-private-feed-that-proxies-pypi.md) | The organization's Python index is a private Azure Artifacts feed that proxies PyPI | Accepted |

## Authoring

Copy [`template.md`](./template.md), take the next `NNNN`, keep it short, and link the canonical
source where the decision is implemented rather than restating it.
