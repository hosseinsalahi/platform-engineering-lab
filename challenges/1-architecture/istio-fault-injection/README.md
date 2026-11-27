# Istio Fault Injection

**Time:** 8 minutes
**Skills tested:** Istio, Chaos Engineering, VirtualService

## Context

The QA team needs to verify that the `frontend` application handles `backend` failures gracefully.
You need to simulate a 500 error on the `backend` service.

## Task

Create an Istio `VirtualService` named `backend-fault` in the `cnpe-fault` namespace that targets the `backend` service.
Configure it to inject a `HTTP 500` error for **50%** of the traffic.

## Verification

The exercise validates:
1.  VirtualService `backend-fault` exists
2.  Hosts is set to `backend`
3.  Fault injection is configured with:
    *   Percentage: 50
    *   HTTP Status: 500

## Allowed Documentation

- [Istio Fault Injection](https://istio.io/latest/docs/tasks/traffic-management/fault-injection/)
