# Solution: Create a Gatekeeper Constraint

## The Constraint

`K8sRequiredLabels` is the CRD that Gatekeeper generated from the ConstraintTemplate. An
instance of it — a Constraint — supplies the `match` scope and the `parameters` the Rego
reads as `input.parameters`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: ns-must-have-team-label
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
    excludedNamespaces:
      - "kube-*"
      - "kuttl-*"
      - "gatekeeper-system"
      - "local-path-storage"
  parameters:
    labels: ["team"]
```

## Why the exclusions matter

A Constraint matching `Namespace` runs on every namespace creation in the cluster, and
Gatekeeper has no built-in carve-out for system components. Without
`excludedNamespaces`, this policy rejects namespaces created by controllers, by the
installer, and by the test harness — KUTTL creates a fresh `kuttl-<random>` namespace per
test run, so an unscoped version of this Constraint makes the exercise unable to start,
and can wedge a real cluster the same way.

`excludedNamespaces` accepts a trailing `*` wildcard, so `kube-*` covers `kube-system`,
`kube-public`, and `kube-node-lease` in one entry. For a Namespace object the match is
evaluated against the namespace's own name.

## Verification

```bash
kubectl get k8srequiredlabels ns-must-have-team-label -o yaml

# Denied: no team label
kubectl create namespace no-owner

# Admitted: label present
kubectl create namespace payments --dry-run=server -o yaml
```

Gatekeeper also reports offending existing objects in the Constraint's
`status.violations`, since audit runs independently of admission.

## Key Concepts

1. **Template vs Constraint**: the ConstraintTemplate carries the Rego and defines a new
   CRD; each Constraint is an instance of that CRD binding parameters to a scope.
2. **`match`** narrows by kind, namespace, label selector, and scope — it is the only
   thing standing between a policy and the entire cluster.
3. **Audit vs admission**: admission blocks new and updated objects; the audit loop
   reports pre-existing violations without deleting anything.
