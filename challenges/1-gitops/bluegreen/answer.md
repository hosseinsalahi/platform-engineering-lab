# Solution: Configure Blue/Green Deployment

## Create Services and Rollout

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: payment-api-active
  namespace: cnpe-bluegreen-test
spec:
  selector:
    app: payment-api
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: payment-api-preview
  namespace: cnpe-bluegreen-test
spec:
  selector:
    app: payment-api
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: payment-api
  namespace: cnpe-bluegreen-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-api
  template:
    metadata:
      labels:
        app: payment-api
    spec:
      containers:
        - name: payment-api
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
  strategy:
    blueGreen:
      activeService: payment-api-active
      previewService: payment-api-preview
      autoPromotionEnabled: false
EOF
```

## Verification

```bash
# Check services
kubectl get svc -n cnpe-bluegreen-test

# Check rollout status
kubectl get rollout payment-api -n cnpe-bluegreen-test
kubectl argo rollouts status payment-api -n cnpe-bluegreen-test
```

## Key Concepts

1. **Active Service** - Routes production traffic to stable ReplicaSet
2. **Preview Service** - Routes test traffic to new ReplicaSet during rollout
3. **autoPromotionEnabled: false** - Requires manual promotion after testing
4. **No version selectors** - Argo Rollouts manages pod selection via rollout-pod-template-hash

## Reference: Promotion Commands

```bash
# After testing preview, promote to active
kubectl argo rollouts promote payment-api -n cnpe-bluegreen-test

# Or abort if issues found
kubectl argo rollouts abort payment-api -n cnpe-bluegreen-test
```
