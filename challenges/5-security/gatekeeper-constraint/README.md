# Exercise: Create a Gatekeeper Constraint

Create a Gatekeeper `Constraint` from an existing `ConstraintTemplate` to require an
ownership label on namespaces.

**Time:** 6 minutes
**Skills tested:** Gatekeeper Constraints, admission policy scoping

## The Scenario

The platform team wants every namespace to carry a `team` label for cost allocation and
ownership tracking. A `ConstraintTemplate` named `K8sRequiredLabels` already exists; it
takes a `labels` parameter and rejects objects missing any of them.

## The Goal

1. Create a `Constraint` named `ns-must-have-team-label` that uses the
   `K8sRequiredLabels` template to require the `team` label on `Namespace` objects.
2. Scope it safely. A Namespace constraint applies at admission across the whole
   cluster, so it will also reject namespaces created by system components and by the
   test harness itself. Exclude the `kube-*` and `kuttl-*` namespace patterns, plus
   `gatekeeper-system` and `local-path-storage`, using `spec.match.excludedNamespaces`.
3. Confirm enforcement: creating a namespace without a `team` label must be rejected,
   while one with the label is admitted.

## Verification

The exercise checks that the Constraint exists with the right parameters, that an
unlabelled namespace is denied, that a labelled one is admitted, and that excluded
namespace patterns still work.

## Allowed Documentation

- [Gatekeeper Constraints](https://open-policy-agent.github.io/gatekeeper/website/docs/howto)
- [Match and scope](https://open-policy-agent.github.io/gatekeeper/website/docs/howto#constraints)
