# Solution: Troubleshoot Operator Not Reconciling

## Diagnosis Steps

```bash
# Check operator logs
kubectl logs -n cnpe-operator-test -l app=backup-operator

# Test if operator SA can access CRs
kubectl auth can-i list databasebackups.platform.cnpe.io \
  --as=system:serviceaccount:cnpe-operator-test:backup-operator \
  -n cnpe-operator-test
# Returns: no

# Check current role permissions
kubectl get role backup-operator-role -n cnpe-operator-test -o yaml
# Missing: databasebackups resource
```

## Solution (kubectl edit - fastest)

```bash
kubectl edit role backup-operator-role -n cnpe-operator-test
# Add this rule:
# - apiGroups: ["platform.cnpe.io"]
#   resources: ["databasebackups"]
#   verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

## Solution (kubectl patch)

```bash
kubectl patch role backup-operator-role -n cnpe-operator-test --type='json' -p='[
  {"op":"add","path":"/rules/-","value":{
    "apiGroups":["platform.cnpe.io"],
    "resources":["databasebackups"],
    "verbs":["get","list","watch","create","update","patch","delete"]
  }}
]'
```

## Why This Matters

Operators commonly fail due to:
- **Missing RBAC**: Can't watch/list resources
- **Wrong apiGroup**: CRDs use custom groups
- **Scope mismatch**: ClusterRole vs Role
- **Incorrect WATCH_NAMESPACE**: Operator is watching the wrong namespace for resources.

## The Second Problem

The operator's deployment is configured with a `WATCH_NAMESPACE` environment variable that is set to `wrong-namespace`. This causes the operator to watch for `DatabaseBackup` resources in the `wrong-namespace` instead of the `cnpe-operator-test` namespace.

## The Solution

To fix this, you need to remove the `WATCH_NAMESPACE` environment variable from the operator's deployment, or set it to the correct namespace.
```bash
kubectl edit deployment backup-operator -n cnpe-operator-test
# Remove the WATCH_NAMESPACE environment variable, or set its value to "cnpe-operator-test"
```
