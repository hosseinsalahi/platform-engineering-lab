# Solution: Configure Istio Traffic Splitting

## Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: payment-routing
  namespace: cnpe-mesh-test
spec:
  hosts:
    - payment-service
  http:
    - route:
        - destination:
            host: payment-service
            subset: stable
          weight: 90
        - destination:
            host: payment-service
            subset: canary
          weight: 10
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: payment-versions
  namespace: cnpe-mesh-test
spec:
  host: payment-service
  subsets:
    - name: stable
      labels:
        version: v1
    - name: canary
      labels:
        version: v2
EOF
```

## Why This Matters

Traffic splitting enables:
- **Gradual rollouts**: Test new versions with limited traffic
- **Risk mitigation**: Quick rollback by adjusting weights
- **A/B testing**: Compare version performance with real traffic
