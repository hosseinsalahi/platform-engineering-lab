# Solution

Edit the ServiceMonitor to match the labels of the Service.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-monitor
  namespace: cnpe-observability
spec:
  selector:
    matchLabels:
      app: payment # Changed from payment-wrong
  endpoints:
  - port: http
  namespaceSelector:
    matchNames:
    - cnpe-observability
```
