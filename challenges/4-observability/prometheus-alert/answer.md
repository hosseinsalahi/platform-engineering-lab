# Solution: Fix Prometheus Alerting Rule

## Issues

1. Missing `release: prometheus-stack` label (rule not discovered)
2. Wrong metric name `container_memory_usage` (should be `container_memory_working_set_bytes`)
3. Missing `team` label for alert routing
4. Missing `description` annotation with pod info

## Fixed PrometheusRule

```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cnpe-memory-alert
  namespace: monitoring
  labels:
    app: kube-prometheus-stack
    release: prometheus-stack
spec:
  groups:
  - name: cnpe.rules
    rules:
    - alert: CnpeHighMemoryUsage
      expr: container_memory_working_set_bytes{namespace="cnpe-critical"} > 100 * 1024 * 1024
      for: 1m
      labels:
        severity: warning
        team: platform
      annotations:
        summary: "High memory usage detected"
        description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is using more than 100Mi memory."
EOF
```

## Key Points

- **Release label**: prometheus-operator uses `release: prometheus-stack` to discover rules
- **Correct metric**: `container_memory_working_set_bytes` is the actual memory metric (not `container_memory_usage`)
- **Team label**: Essential for alert routing via Alertmanager
- **Description template**: Use `{{ $labels.pod }}` for dynamic pod name in alerts
