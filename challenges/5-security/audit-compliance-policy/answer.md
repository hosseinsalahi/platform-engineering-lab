# Solution: Generate Policy Compliance Audit Trails with Kyverno

## Diagnosis

```bash
kubectl get clusterpolicy audit-image-provenance -o yaml
kubectl get policyreports -n cnpe-compliance -o yaml
```

Three issues prevent compliance audit reporting:
1. `spec.background: false` stops Kyverno from scanning pre-existing Deployments.
2. `match.any[0].resources.namespaces` targets `cnpe-other-ns` instead of `cnpe-compliance`.
3. `validate.failureAction` is `Enforce` rather than `Audit`.

## Fix the Audit Policy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: audit-image-provenance
spec:
  background: true
  rules:
    - name: require-sbom-annotation
      match:
        any:
          - resources:
              kinds:
                - Deployment
              namespaces:
                - cnpe-compliance
      validate:
        failureAction: Audit
        message: "Deployments should declare a security.cnpe.io/sbom-uri annotation."
        pattern:
          metadata:
            annotations:
              security.cnpe.io/sbom-uri: "?*"
```

## Verification

```bash
kubectl get policyreports -n cnpe-compliance
kubectl get policyreports -n cnpe-compliance -o yaml
```

## Key Concepts

1. **`background: true`** instructs Kyverno's reports controller to evaluate existing
   cluster resources, not just admission requests.
2. **`failureAction: Audit`** records non-compliant resources in `PolicyReport` objects
   (`wgpolicyk8s.io/v1alpha2`) without rejecting workloads during rollout.
3. **Standardized PolicyReports** allow compliance dashboards and audit pipelines to track
   pass/fail posture across namespaces over time.
