# Exercise: Make the Platform's DORA Signals Real

**Time:** 8 minutes
**Skills tested:** Prometheus Operator, recording rules, platform measurement

## The Scenario

Leadership asked the platform team for DORA numbers. Someone wrote a `PrometheusRule`
with two recording rules — a deployment-frequency counter and a change-failure ratio —
applied it to the cluster, and put a panel on a dashboard.

The panel has been empty ever since. The object exists; `kubectl get prometheusrule`
shows it. Prometheus has never evaluated it.

## The Goal

1. Work out why a `PrometheusRule` that exists in the cluster is invisible to Prometheus.
2. Fix it, and fix the second problem you find once it is being read.
3. Confirm Prometheus has actually loaded the rule group — not merely that the object
   exists.

## Notes on the metrics

These are proxies, not certified DORA metrics, and the exercise is about wiring rather
than about metric theory:

- **Deployment frequency** — how often Deployment specs change, via
  `kube_deployment_status_observed_generation`.
- **Change failure ratio** — containers stuck in `CrashLoopBackOff` over running pods.

Real DORA measurement needs deploy and incident events from your delivery pipeline, not
just cluster state. That is the point worth taking away: the platform can measure some of
this itself, and the rest has to come from somewhere else.

## Verification

The exercise checks the rule is selectable by the Prometheus instance, that both
recording-rule names are valid, and that the group appears in Prometheus's own rules API.

## Allowed Documentation

- [Prometheus Operator: PrometheusRule](https://prometheus-operator.dev/docs/developer/alerting/)
- [Recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Metric naming](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels)
