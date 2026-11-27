# Diagnose and Remediate Pod Failure

**Time:** 7 minutes
**Skills tested:** Incident Diagnosis, Troubleshooting, Root Cause Analysis

## Context

The order-processor deployment is failing. Users report orders are not being processed. You need to diagnose the issue using logs, events, and pod status, then fix the problem.

## Task

Diagnose and fix the failing deployment in `cnpe-incident-test` namespace:

1. Investigate why pods are failing (check events, logs, describe)
2. Identify the root cause
3. Fix the deployment configuration
4. Verify pods are running

## Hints

- Check `kubectl describe pod` for events
- Check `kubectl logs` for container errors
- Common issues: image pull, resource limits, probes, env vars

## Verification

The exercise validates:
1. Deployment exists with correct configuration
2. Pod is running successfully
3. Deployment has available replicas

## Allowed Documentation

- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
