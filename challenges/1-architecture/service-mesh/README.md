# Configure Istio Traffic Splitting

**Time:** 7 minutes
**Skills tested:** Service Mesh, Istio VirtualService, Traffic Management

## Context

The platform team is rolling out a new version of the payment service. You need to configure Istio to split traffic between v1 and v2 using a VirtualService, sending 90% to stable and 10% to canary.

## Task

Configure traffic splitting in the `cnpe-mesh-test` namespace:

1. Create a **VirtualService** for traffic routing
2. Create **DestinationRules** for subset definitions
3. Verify traffic can be routed to both versions

## Requirements

**VirtualService** (`payment-routing`):
- Host: payment-service
- Route 90% traffic to subset `stable` (v1)
- Route 10% traffic to subset `canary` (v2)

**DestinationRule** (`payment-versions`):
- Host: payment-service
- Subsets: `stable` (version: v1), `canary` (version: v2)

## Verification

The exercise validates:
1. VirtualService exists with correct host
2. Traffic weights are 90/10
3. DestinationRule has both subsets defined

## Allowed Documentation

- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [VirtualService Reference](https://istio.io/latest/docs/reference/config/networking/virtual-service/)
