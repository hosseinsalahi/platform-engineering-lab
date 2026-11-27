# Solution: Configure Sidecar Logging and Log Scraping Annotations

## Diagnosis

```bash
kubectl get deploy checkout-worker -n cnpe-logging -o yaml
kubectl logs deploy/checkout-worker -n cnpe-logging -c log-streamer
```

Two issues prevent centralized log collection:
1. `spec.template.metadata.annotations` has `logging.cnpe.io/scrape: "false"` and lacks
   `logging.cnpe.io/format: "json"`.
2. The `log-streamer` sidecar mounts the `varlog` volume at `/wrong/path` instead of
   `/var/log/app`, so `tail -n+1 -F /var/log/app/app.log` never sees the file written by
   the `app` container.

## Fix the Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-worker
  namespace: cnpe-logging
  labels:
    app: checkout-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout-worker
  template:
    metadata:
      labels:
        app: checkout-worker
      annotations:
        logging.cnpe.io/scrape: "true"
        logging.cnpe.io/format: "json"
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
            - |
              while true; do
                printf '{"level":"info","service":"checkout","msg":"order processed"}\n' >> /var/log/app/app.log
                sleep 5
              done
          volumeMounts:
            - name: varlog
              mountPath: /var/log/app
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
        - name: log-streamer
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
            - tail -n+1 -F /var/log/app/app.log
          volumeMounts:
            - name: varlog
              mountPath: /var/log/app
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
      volumes:
        - name: varlog
          emptyDir: {}
```

```bash
kubectl rollout status deployment/checkout-worker -n cnpe-logging --timeout=120s
```

## Verification

```bash
kubectl logs deploy/checkout-worker -n cnpe-logging -c log-streamer --tail=10
```

## Key Concepts

1. **Streaming sidecar pattern**: When legacy applications write logs to local files instead of
   `stdout`, a lightweight sidecar sharing an `emptyDir` volume tails the file to `stdout` so
   node-level log agents (Fluent Bit, Promtail, Vector) can collect it uniformly.
2. **Scraping and parser annotations**: Cluster log shippers use pod annotations to opt pods
   in/out and select the structured log parser (`json`, `logfmt`, etc.).
