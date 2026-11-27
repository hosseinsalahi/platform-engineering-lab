# Configure Network Policies for Multi-Tenancy

**Time:** 7 minutes

## Context

The platform team is implementing multi-tenancy isolation. Two tenant namespaces exist:
- `tenant-alpha` - runs a frontend and backend
- `tenant-beta` - runs separate workloads

Currently there's no network isolation - any pod can talk to any other pod across namespaces.

## Task

### Phase 1: Default Deny Policy

Create a default-deny NetworkPolicy in `tenant-alpha` that blocks all ingress traffic by default.

### Phase 2: Allow Frontend to Backend

Create a NetworkPolicy that allows the frontend pods (label: `app=frontend`) to reach backend pods (label: `app=backend`) on port 8080.

### Phase 3: Allow Monitoring Access

Create a NetworkPolicy that allows pods from the monitoring tenant namespace
(`cnpe-monitoring`, labelled `purpose: monitoring`) to scrape metrics from all pods in
`tenant-alpha` on port 9090. Select it by label, not by name.

## Verification

Traffic should work:
- `frontend` → `backend:8080` (same namespace)
- `cnpe-monitoring` → `any-pod:9090` (cross-namespace)

Traffic should be blocked:
- `tenant-beta` → `tenant-alpha` (cross-tenant)
- External → `tenant-alpha` (no ingress)

## Allowed Documentation

- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Declare Network Policy](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
