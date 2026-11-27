# Solution: Configure Network Policies

## Phase 1: Default Deny

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

## Phase 2: Allow Frontend to Backend

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: tenant-alpha
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF
```

## Phase 3: Allow Monitoring

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: monitoring
    ports:
    - protocol: TCP
      port: 9090
EOF
```

## All-in-One (faster for exam)

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: tenant-alpha
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: tenant-alpha
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: monitoring
    ports:
    - port: 9090
EOF
```

## Verify

```bash
# List policies
kubectl get networkpolicy -n tenant-alpha

# Test from frontend to backend (if you have exec)
kubectl exec -n tenant-alpha frontend -- wget -qO- --timeout=2 backend:8080

# Test cross-namespace (should timeout/fail)
kubectl exec -n tenant-beta workload -- wget -qO- --timeout=2 backend.tenant-alpha:8080
```

## Key Concepts

- **Empty podSelector `{}`** = applies to all pods in namespace
- **Default deny** = creates baseline isolation
- **Policies are additive** = multiple policies combine (OR logic)
- **namespaceSelector** = cross-namespace access control
- **Both selectors in one `from` rule** = AND logic
- **Separate items in `from` array** = OR logic
