# Fix Broken ServiceMonitor

**Time:** 7 minutes
**Skills tested:** Prometheus, ServiceMonitor, Label Selection

## Context

The `payment-service` is running in namespace `cnpe-observability`, but Prometheus is not scraping its metrics. A ServiceMonitor resource exists, but it seems to be misconfigured.

## Task

Fix the ServiceMonitor `payment-monitor` in namespace `cnpe-observability` so that it correctly selects the `payment-service`.

1.  Identify the mismatch between the ServiceMonitor selector and the Service labels.
2.  Update the ServiceMonitor to select the correct Service.

## Verification

The exercise validates:
1.  ServiceMonitor exists
2.  ServiceMonitor selects `app: payment`
3.  ServiceMonitor has correct namespace selector (or matchNames)

## Allowed Documentation

- [Prometheus Operator ServiceMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/user-guides/getting-started.md)
