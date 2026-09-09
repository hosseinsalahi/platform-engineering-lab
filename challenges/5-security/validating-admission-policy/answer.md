# Solution: Fix the ValidatingAdmissionPolicy

## Diagnosis

```bash
kubectl get validatingadmissionpolicy require-team-label -o yaml
kubectl get validatingadmissionpolicybinding require-team-label-binding -o yaml
```

The binding is fine: it targets `cnpe-vap-test` with `validationActions: ["Deny"]`. Two
things in the policy itself combine to let unlabelled Deployments through:

1. The expression `object.metadata.labels['team'] != ''` **indexes** a map key. In CEL,
   indexing a key that is absent raises an evaluation error rather than returning false.
   A Deployment with no labels at all — the exact case being guarded against — errors.
2. `failurePolicy: Ignore` says what to do with that error: admit the object. So the one
   input the policy exists to catch is the one input it lets through.

This is the classic fail-open admission bug, and it is quiet: nothing is logged as a
rejection because nothing was rejected.

## Fix the policy

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-team-label
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: "has(object.metadata.labels) && 'team' in object.metadata.labels && object.metadata.labels['team'] != ''"
      message: "Deployments must carry a non-empty 'team' label."
```

`has()` guards the `labels` field itself (it is optional on every object), `in` tests for
the key without indexing, and only then is indexing safe. CEL short-circuits `&&` left to
right, so the final comparison never runs on a missing key.

`failurePolicy: Fail` is the safe default for a policy that is meant to block: if the
expression cannot be evaluated, the request is rejected rather than waved through.

## Deploy a compliant workload

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  namespace: cnpe-vap-test
  labels:
    team: payments
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout-api
  template:
    metadata:
      labels:
        app: checkout-api
        team: payments
    spec:
      containers:
      - name: checkout-api
        image: nginx:1.25
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
```

## Verification

```bash
# Denied
kubectl create deployment unlabelled --image=nginx:1.25 -n cnpe-vap-test

# Admitted
kubectl get deploy checkout-api -n cnpe-vap-test
```

## Key Concepts

1. **ValidatingAdmissionPolicy is in-tree.** The API server evaluates CEL itself — no
   webhook to deploy, no certificate to rotate, no extra network hop, and no failure mode
   where an unreachable webhook stalls admission. It went GA in Kubernetes 1.30.
2. **Policy, binding, and parameters are separate objects.** The policy is the logic; the
   binding decides where it applies and whether violations `Deny`, `Warn`, or `Audit`.
   The same policy can be bound strictly in production and in audit mode elsewhere.
3. **`failurePolicy` governs evaluation errors, not violations.** `Ignore` fails open —
   appropriate for advisory checks, dangerous for guardrails.
4. **CEL is total, not forgiving.** Missing keys, wrong types, and out-of-range indexes
   are errors. Write expressions defensively with `has()` and `in`.
5. **What VAP cannot do:** call external services, look up other cluster objects, mutate,
   or generate. Those still need Kyverno or Gatekeeper — which is why this repo teaches
   all three.
