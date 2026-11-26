# Solution: Configure Jaeger Tracing

## Phase 1 & 2: Fix Environment Variables

```bash
kubectl edit deployment order-service -n cnpe-tracing-test
```

Update environment variables:
```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: order-service
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://jaeger-collector:4317"
  - name: OTEL_PROPAGATORS
    value: "tracecontext,baggage"
```

## One-liner with patch

```bash
kubectl patch deployment order-service -n cnpe-tracing-test --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/1/value", "value": "http://jaeger-collector:4317"},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "OTEL_PROPAGATORS", "value": "tracecontext,baggage"}}
]'
```

## Complete Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: cnpe-tracing-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
        - name: app
          image: nginx:1.25
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
          env:
            - name: OTEL_SERVICE_NAME
              value: order-service
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://jaeger-collector:4317"
            - name: OTEL_PROPAGATORS
              value: "tracecontext,baggage"
EOF
```

## Key Concepts

1. **OTEL_EXPORTER_OTLP_ENDPOINT**: Where to send traces (Jaeger collector)
2. **OTEL_PROPAGATORS**: How trace context is passed between services
   - `tracecontext`: W3C Trace Context (standard)
   - `baggage`: W3C Baggage for custom context

3. **Jaeger Ports**:
   - 4317: OTLP gRPC
   - 4318: OTLP HTTP
   - 16686: UI

## Verification

```bash
# Check Jaeger UI
kubectl port-forward svc/jaeger-query -n cnpe-tracing-test 16686:16686

# View in browser: http://localhost:16686
```
