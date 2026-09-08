# Solution: Fix the Istio Canary Configuration

## Diagnosis

```bash
kubectl get rollout echo -n cnpe-istio-canary
kubectl get virtualservice,destinationrule -n cnpe-istio-canary
kubectl get svc -n cnpe-istio-canary
```

The Rollout is Healthy and the VirtualService looks right — it routes `primary` between
`echo-stable` and `echo-canary`. The DestinationRule is the broken one: its `spec.host`
is `echo`, and there is no Service by that name. The two Services are `echo-stable` and
`echo-canary`.

A DestinationRule whose host does not resolve is silently ignored by Istio. Nothing
errors, no Rollout condition turns false, and traffic keeps flowing — but the `stable`
and `canary` subsets never apply, so any policy attached to them (TLS settings, outlier
detection, load balancer configuration) is quietly absent during a canary release.

## Fix the DestinationRule host

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: echo
  namespace: cnpe-istio-canary
spec:
  host: echo-stable
  subsets:
  - name: stable
    labels:
      app: echo
  - name: canary
    labels:
      app: echo
```

`host` must name a Service reachable from this namespace — either the short name of a
Service in the same namespace, or an FQDN such as
`echo-stable.cnpe-istio-canary.svc.cluster.local`.

## Verification

```bash
kubectl get destinationrule echo -n cnpe-istio-canary -o yaml
istioctl analyze -n cnpe-istio-canary
```

`istioctl analyze` reports a DestinationRule pointing at a non-existent host, which is
the fastest way to catch this class of bug before it reaches production.

## Key Concepts

1. **Argo Rollouts host-based Istio routing** rewrites the *weights* on the named
   VirtualService route (`primary` here) between `stableService` and `canaryService`. It
   does not require subsets, which is why the rollout stays Healthy despite the broken
   DestinationRule.
2. **Silent failure**: an unresolvable DestinationRule host is not a hard error in Istio.
   Config that is ignored rather than rejected is the hardest kind to notice.
3. **Subsets are for policy, not routing weight**: they attach per-version traffic policy.
   With subset-based routing (`trafficRouting.istio.destinationRule`), Rollouts manages
   the subsets' labels itself and a bad host breaks the release outright.
