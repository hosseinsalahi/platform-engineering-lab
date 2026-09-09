# Exercise: Fix a ValidatingAdmissionPolicy

**Time:** 8 minutes
**Skills tested:** ValidatingAdmissionPolicy, CEL, admission failure semantics

## The Scenario

The platform team wants every Deployment in `cnpe-vap-test` to carry a `team` label for
ownership tracking. They wrote a `ValidatingAdmissionPolicy` rather than reaching for a
webhook engine, since Kubernetes evaluates CEL in-process with nothing to install.

The policy is deployed and bound, but unlabelled Deployments are still being created.

## The Goal

1. Work out why the policy admits objects it should reject. There are two problems, and
   they compound: one in how evaluation failures are handled, one in the CEL expression.
2. Fix both so a Deployment without a `team` label is denied.
3. Confirm a Deployment *with* the label is still admitted and becomes ready — a policy
   that rejects everything is not a fix.

## Hints

- `kubectl get validatingadmissionpolicy require-team-label -o yaml`
- CEL indexing a map key that does not exist is an *error*, not `false`. What the policy
  does with that error is controlled by `spec.failurePolicy`.
- `has()` and the `in` operator let you test for a key without indexing it.

## Verification

The exercise checks that evaluation errors are no longer ignored, that an unlabelled
Deployment is rejected, and that a labelled one runs.

## Allowed Documentation

- [Validating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [CEL in Kubernetes](https://kubernetes.io/docs/reference/using-api/cel/)
