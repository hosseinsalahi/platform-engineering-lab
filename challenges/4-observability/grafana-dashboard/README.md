# Fix Broken Grafana Dashboard

**Time:** 7 minutes

## Context

The platform team created a custom Grafana dashboard for monitoring the `cnpe-apps` namespace, but it's showing "No data" for all panels. The dashboard was deployed as a ConfigMap but something is misconfigured.

## Task

Fix the Grafana dashboard ConfigMap so it properly displays metrics.

Hints:
- Check the datasource configuration in the dashboard JSON
- The Prometheus datasource in this cluster is named `prometheus`
- Dashboard ConfigMaps need the correct label to be discovered by Grafana
- Verify that the metrics used in the dashboard panels exist in Prometheus

## Allowed Documentation

- [Grafana Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/)
- [Grafana Sidecar Dashboards](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards)
