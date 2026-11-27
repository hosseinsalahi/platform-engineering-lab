# Generate Policy Compliance Audit Trails with Kyverno

**Time:** 8 minutes
**Skills tested:** Kyverno ClusterPolicy, background scanning, PolicyReports

## Context

Security leadership needs an audit trail showing which Deployments in `cnpe-compliance`
declare an SBOM provenance annotation (`security.cnpe.io/sbom-uri`), without blocking
existing workloads while teams onboard.

Two Deployments already exist in `cnpe-compliance`:
- `attested-app` (has `security.cnpe.io/sbom-uri`)
- `legacy-app` (missing the annotation)

However, `kubectl get policyreports -n cnpe-compliance` shows no compliance results for
`audit-image-provenance`.

## Task

Fix `ClusterPolicy` `audit-image-provenance` so that:
1. Background scanning is enabled (`spec.background: true`).
2. Rule `require-sbom-annotation` targets `Deployment` resources in `cnpe-compliance`.
3. Rule `require-sbom-annotation` uses `validate.failureAction: Audit`.
4. Kyverno generates `PolicyReport` entries in `cnpe-compliance` showing both `pass` and
   `fail` results for `audit-image-provenance`.

## Verification

The exercise validates:
1. `spec.background: true` on `audit-image-provenance`.
2. Namespace match is `cnpe-compliance` and `failureAction` is `Audit`.
3. `PolicyReport` objects in `cnpe-compliance` include both `pass` and `fail` entries for
   `audit-image-provenance`.

## Allowed Documentation

- [Kyverno Validation Rules](https://kyverno.io/docs/writing-policies/validate/)
- [Kyverno Policy Reports](https://kyverno.io/docs/policy-reports/)
