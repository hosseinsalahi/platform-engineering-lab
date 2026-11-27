# Configure Blue/Green Deployment with Argo Rollouts

**Time:** 7 minutes
**Skills tested:** Argo Rollouts, Blue/Green Strategy, Service Configuration

## Context

The platform team wants to implement Blue/Green deployments for the `payment-api` service. The application is currently running as a standard Deployment. You need to create the Argo Rollout and configure the services for Blue/Green traffic switching.

## Task

Set up Blue/Green deployment for `payment-api` in namespace `cnpe-bluegreen-test`:

1. Create a **Service** named `payment-api-active` for production traffic
2. Create a **Service** named `payment-api-preview` for testing new versions
3. Create an Argo **Rollout** named `payment-api` with Blue/Green strategy
4. Configure the Rollout to use both services for traffic management

## Requirements

- Both services must select pods with label `app: payment-api`
- Services must NOT include version-specific selectors (Argo Rollouts manages this)
- Rollout must reference `activeService` and `previewService` correctly
- Set `autoPromotionEnabled: false` for manual promotion control

## Verification

The exercise validates:
1. Services exist without version selectors
2. Rollout references correct service names
3. Rollout becomes healthy

## Allowed Documentation

- [Argo Rollouts Blue/Green](https://argo-rollouts.readthedocs.io/en/stable/features/bluegreen/)
- [Rollout Specification](https://argo-rollouts.readthedocs.io/en/stable/features/specification/)
