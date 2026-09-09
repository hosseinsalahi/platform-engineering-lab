# Solution: Fix Broken Kyverno Policy

## Diagnosis

```bash
kubectl get clusterpolicy require-memory-limits -o yaml
```

Two bugs are visible in the policy spec:

1. `validationFailureAction: Audit` only records violations in a PolicyReport; it never
   rejects a Pod. It must be `Enforce`.
2. `match.any[0].resources.namespaces` lists `cnpe-other-namespace`, so the rule never
   selects Pods in `cnpe-security-test`.

## Phases 1 and 2: Apply the corrected policy

Both bugs live in the same object, so a single apply fixes them:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-memory-limits
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: require-memory-limits
    match:
      any:
      - resources:
          kinds:
          - Pod
          namespaces:
          - cnpe-security-test
    validate:
      message: "Memory limits are required for all containers."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
```

## Phase 3: Admit a compliant Pod

The final assert requires a running Pod that satisfies the policy, proving the rule
admits valid workloads rather than blocking everything:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
  namespace: cnpe-security-test
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    resources:
      limits:
        memory: "128Mi"
```

## Verify the policy blocks violations

A Pod without limits must now be rejected by the admission webhook:

```bash
kubectl run test-pod --image=nginx -n cnpe-security-test
# Expected: admission webhook denies the request with
# "Memory limits are required for all containers."
```

## Key Concepts

1. **validationFailureAction**: `Audit` only logs violations, `Enforce` blocks them
2. **match.resources.namespaces**: Limits policy to specific namespaces
3. **validate.pattern**: Uses Kyverno's pattern matching to check resource fields
4. `?*` means "any non-empty value must be present"

## Reference: kyverno commands

```bash
kubectl get clusterpolicy                      # List policies
kubectl get policyreport -A                    # View policy reports
kyverno apply policy.yaml --resource pod.yaml  # Test policy locally
```
