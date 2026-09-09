# Exercise: Fix a Broken Istio Canary Configuration

**Time:** 6 minutes
**Skills tested:** Argo Rollouts, Istio VirtualService and DestinationRule, silent misconfiguration

## The Scenario

The `echo` service in `cnpe-istio-canary` is released with Argo Rollouts using a canary
strategy, with Istio shifting traffic between the `echo-stable` and `echo-canary`
Services. The rollout reports Healthy, but the platform team has noticed that the traffic
policy they attached to the `stable` and `canary` subsets never takes effect during a
release.

## The Goal

- Work out why the subsets are not being applied, even though nothing reports an error.
- Fix the misconfigured Istio resource.
- Leave the Rollout healthy and the VirtualService route wiring intact.

## Verification

The exercise checks that the DestinationRule resolves to a Service that exists, that both
subsets are still defined, that the Rollout is Healthy, and that the `primary` route is
unchanged.

## Allowed Documentation

- [Argo Rollouts Traffic Management with Istio](https://argo-rollouts.readthedocs.io/en/stable/traffic-management/istio/)
- [Istio DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/)
- [Istio VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/)
