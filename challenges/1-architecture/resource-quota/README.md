# Configure Multi-Tenant Resource Isolation

**Time:** 7 minutes
**Skills tested:** ResourceQuota, LimitRange, Namespace Isolation

## Context

The platform team is onboarding `team-alpha` to the cluster. To ensure fair resource distribution and prevent noisy neighbors, you must configure resource quotas and default limits for their namespace.

## Task

Configure resource isolation for the `team-alpha` namespace:

1. Create a **ResourceQuota** to limit total namespace resources
2. Create a **LimitRange** to set default container limits
3. Verify defaults are applied to new pods

## Requirements

**ResourceQuota** (`team-alpha-quota`):
- CPU requests: 4 cores, limits: 8 cores
- Memory requests: 8Gi, limits: 16Gi
- Maximum 10 pods

**LimitRange** (`team-alpha-limits`):
- Default CPU limit: 500m, request: 100m
- Default memory limit: 512Mi, request: 128Mi
- Max CPU per container: 2 cores
- Max memory per container: 4Gi

**Test Pod:**
- Create pod `test-defaults` without resource specs
- Verify LimitRange defaults are applied

## Verification

The exercise validates:
1. ResourceQuota exists with correct limits
2. LimitRange exists with defaults
3. Test pod has default resources applied

## Allowed Documentation

- [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
