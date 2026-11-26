# Pod Disruption Budget

**Domain:** Platform Architecture (15%)
**Competency:** Designing Resilient Workloads
**Time:** 7 minutes

## Context

A team runs a stateless web service with 2 replicas. During node maintenance or voluntary disruptions, both pods can be evicted at the same time, causing downtime.

## Task

Fix the PodDisruptionBudget so that at least **1 pod stays available** during voluntary disruptions.

## Requirements

- `PodDisruptionBudget` name: `web-pdb`
- Namespace: `cnpe-pdb`
- `minAvailable: 1`
- Selector must match the `web` Deployment pods

## Hints

```bash
kubectl get deploy,pods,pdb -n cnpe-pdb
kubectl describe pdb web-pdb -n cnpe-pdb
```

## Allowed Documentation

- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

