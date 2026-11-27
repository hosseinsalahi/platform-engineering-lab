# Fix Prometheus Alerting Rule

**Time:** 7 minutes

## Context

The platform team created a PrometheusRule to alert when pods in namespace `cnpe-critical` are consuming excessive memory. However, the alert isn't firing even though pods are clearly over the threshold.

The SRE team suspects the PromQL expression or rule configuration is broken.

## Task

Fix the PrometheusRule `cnpe-memory-alert` in namespace `monitoring` so it:
1. Has a valid PromQL expression
2. Is properly configured to fire when memory exceeds 100Mi
3. Has appropriate labels for routing

## Allowed Documentation

- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [PrometheusRule CRD](https://prometheus-operator.dev/docs/api-reference/api/#monitoring.coreos.com/v1.PrometheusRule)
- [PromQL Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
