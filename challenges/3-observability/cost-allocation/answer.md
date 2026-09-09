# Solution: Fix OpenCost Cost Allocation

Three objects need the same three labels: the namespace, the Deployment's own metadata,
and — most importantly — the pod template, because that is where resource consumption is
actually measured.

## Apply the labels

```bash
# Namespace
kubectl label ns cnpe-team-alpha cost-center=cc-platform team=alpha environment=dev --overwrite

# Deployment metadata
kubectl label deploy cost-test-app -n cnpe-team-alpha cost-center=cc-platform team=alpha environment=dev --overwrite

# Pod template (triggers a rollout, so the new pods carry the labels)
kubectl patch deploy cost-test-app -n cnpe-team-alpha --type=merge -p '
spec:
  template:
    metadata:
      labels:
        cost-center: cc-platform
        team: alpha
        environment: dev
'
```

## Alternative: with an editor

```bash
kubectl edit deployment cost-test-app -n cnpe-team-alpha
```

Add the labels in both places — `metadata.labels` and `spec.template.metadata.labels`:

```yaml
metadata:
  labels:
    cost-center: cc-platform   # <-- add here
    team: alpha
    environment: dev
spec:
  template:
    metadata:
      labels:
        app: cost-test
        cost-center: cc-platform   # <-- and here
        team: alpha
        environment: dev
```

## Verification

```bash
kubectl get ns cnpe-team-alpha --show-labels
kubectl get deploy cost-test-app -n cnpe-team-alpha --show-labels
kubectl get pods -n cnpe-team-alpha --show-labels
```

## Why This Matters

OpenCost aggregates costs by label via the `/allocation` API:

- `aggregate=label:team` — costs by team
- `aggregate=label:cost-center` — costs by cost center

Labels on the Deployment alone are not enough. OpenCost attributes spend from pod-level
resource usage, so a pod template without the labels produces unallocated cost even when
the parent Deployment is labelled correctly. Note that changing the pod template rolls
the Deployment; changing only `metadata.labels` does not.
