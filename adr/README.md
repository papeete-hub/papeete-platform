# Decision log (`ADR-PL-*`)

Decisions owned by **this repo**: what shared, cross-actor/cross-product infrastructure this repo
provisions, and this repo's own boundary against `papeete-deploy` and `papeete-actor`'s
`deploy/terraform/`.

## The log

| ID | Title | Status |
|----|-------|--------|
| [ADR-PL-0001](./ADR-PL-0001-papeete-platform-is-a-standalone-terraform-repo.md) | papeete-platform is a standalone Terraform repo for infra shared across actors and products | Accepted |
| [ADR-PL-0002](./ADR-PL-0002-image-building-is-shared-platform-infrastructure.md) | Image building is shared platform infrastructure: in-cluster rootless BuildKit pushing to a cloud registry | Accepted |

## Authoring

Copy [`template.md`](./template.md), take the next `NNNN`, keep it short, and link the canonical
source where the decision is implemented rather than restating it.
