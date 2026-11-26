# Create Platform CRD for Self-Service

**Time:** 7 minutes

## Context

The platform team wants to enable self-service environment provisioning. Developers should request environments using a custom `Environment` resource instead of asking the platform team to create namespaces manually.

A partial CRD has been created but is incomplete and won't validate properly.

## Task

### Phase 1: Fix the CRD Definition

The `Environment` CRD in namespace `cnpe-platform` is broken. Fix it so that:
- API group is `platform.cnpe.io`
- Resource is `environments` (plural), `environment` (singular)
- It's namespace-scoped
- Schema validates `spec.team` (required string) and `spec.size` (enum: small, medium, large)

### Phase 2: Create a Valid Environment Resource

Once the CRD is working, create an Environment resource:
- Name: `dev-alpha`
- Namespace: `cnpe-platform`
- Team: `alpha`
- Size: `medium`

## Allowed Documentation

- [CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
- [Kubernetes API Conventions](https://kubernetes.io/docs/reference/using-api/api-concepts/)
