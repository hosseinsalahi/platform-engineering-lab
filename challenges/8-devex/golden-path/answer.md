# Solution: Repair the Golden Path

## Diagnosis

```bash
kubectl get clusterpolicy golden-path-namespace -o yaml
kubectl get namespace cnpe-devex-team --show-labels
kubectl get resourcequota,networkpolicy -n cnpe-devex-team
```

Two bugs, and the first hides the second:

1. Both rules select on `golden-path: "true"`, but the label the platform documents — and
   that teams actually set — is `platform.cnpe.io/golden-path: "true"`. The selector never
   matches, so the rules never fire and nothing is generated.
2. Both `generate` blocks hardcode `namespace: default`. Had the selector matched, every
   team's quota and NetworkPolicy would have been written into `default`, colliding with
   each other on the fixed resource names.

The generated namespace has to come from the object that triggered the rule, which
Kyverno exposes as `{{request.object.metadata.name}}`.

## Fix the policy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: golden-path-namespace
spec:
  background: true
  rules:
    - name: add-resource-quota
      match:
        any:
          - resources:
              kinds:
                - Namespace
              selector:
                matchLabels:
                  platform.cnpe.io/golden-path: "true"
      generate:
        apiVersion: v1
        kind: ResourceQuota
        name: golden-path-quota
        namespace: "{{request.object.metadata.name}}"
        synchronize: true
        data:
          spec:
            hard:
              requests.cpu: "2"
              requests.memory: 4Gi
              pods: "20"
    - name: add-default-deny
      match:
        any:
          - resources:
              kinds:
                - Namespace
              selector:
                matchLabels:
                  platform.cnpe.io/golden-path: "true"
      generate:
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        name: default-deny-ingress
        namespace: "{{request.object.metadata.name}}"
        synchronize: true
        data:
          spec:
            podSelector: {}
            policyTypes:
              - Ingress
```

## Onboard the team

The namespace already exists, so labelling it is the trigger:

```bash
kubectl label namespace cnpe-devex-team platform.cnpe.io/golden-path=true --overwrite
```

Generation runs in Kyverno's background controller, so the objects appear a moment later
rather than synchronously:

```bash
kubectl get resourcequota,networkpolicy -n cnpe-devex-team
```

## Key Concepts

1. **`generate` is what makes a golden path self-service.** Validation tells a developer
   they got it wrong; generation means they never had to get it right. The best guardrail
   is one nobody has to write.
2. **`synchronize: true`** makes Kyverno the owner: edit or delete a generated object and
   it is restored. Without it the objects are created once and then drift freely.
3. **`{{request.object.metadata.name}}`** is the trigger's own name. Anything hardcoded in
   a generate rule is a collision waiting for the second tenant.
4. **The opt-in label is an API.** It is the entire developer-facing surface of this
   golden path, which is why a mismatch between the documented label and the policy's
   selector is a platform outage that produces no errors at all.
5. **Generation needs RBAC.** Kyverno's background controller can only create what its
   ClusterRole permits; extending a golden path to a new resource kind often means
   granting that permission first.
