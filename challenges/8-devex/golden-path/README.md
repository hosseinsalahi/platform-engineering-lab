# Exercise: Repair the Golden Path

**Time:** 8 minutes
**Skills tested:** Kyverno generate rules, self-service guardrails, platform UX

## The Scenario

The platform team offers a golden path: a team labels its namespace with
`platform.cnpe.io/golden-path: "true"` and the platform fills in the guardrails for them
— a `ResourceQuota` so one team cannot starve the cluster, and a default-deny
`NetworkPolicy` so the namespace starts closed.

The point is that developers do not write either of those. They opt in with one label and
the platform does the rest.

`cnpe-devex-team` has been onboarded, and nothing was created. Teams have started writing
their own quotas by hand, which is exactly the outcome the golden path exists to prevent.

## The Goal

1. Find why the `golden-path-namespace` policy never fires, and why it would put the
   generated objects in the wrong place if it did.
2. Fix the policy.
3. Onboard `cnpe-devex-team` by giving it the documented label, and confirm the platform
   generates both guardrails into that namespace.

## Verification

The exercise checks that the quota and the default-deny policy exist *in the team's
namespace* with the right contents, that they are owned by Kyverno rather than applied by
hand, and that the namespace carries the opt-in label.

## Allowed Documentation

- [Kyverno generate rules](https://kyverno.io/docs/policy-types/cluster-policy/generate/)
- [Kyverno variables and JMESPath](https://kyverno.io/docs/policy-types/cluster-policy/jmespath/)
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
