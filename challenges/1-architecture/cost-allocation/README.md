# Fix OpenCost Cost Allocation

**Time:** 7 minutes

## Context

The platform team deployed OpenCost for cost visibility, but namespace cost allocation isn't working. The finance team needs accurate showback reports by team namespace.

A developer created namespace `cnpe-team-alpha` but costs aren't appearing in OpenCost reports because required labels are missing.

## Task

1. Add cost allocation labels to the `cnpe-team-alpha` namespace
2. Ensure the test deployment in that namespace also has proper labels

Required labels for cost attribution:
- `cost-center`: The cost center code (use `cc-platform`)
- `team`: Team name (use `alpha`)
- `environment`: Environment type (use `dev`)

## Allowed Documentation

- [OpenCost API](https://www.opencost.io/docs/integrations/api)
- [Kubernetes Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
