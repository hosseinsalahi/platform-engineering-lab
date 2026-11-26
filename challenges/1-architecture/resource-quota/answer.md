# Solution: Configure ResourceQuota and LimitRange

## Phase 1: Create ResourceQuota

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "10"
EOF
```

## Phase 2: Create LimitRange

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: team-alpha-limits
  namespace: team-alpha
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "2"
        memory: 4Gi
EOF
```

## Phase 3: Test Defaults

```bash
kubectl run test-defaults -n team-alpha --image=nginx:1.25 --restart=Never

# Verify defaults were applied
kubectl get pod test-defaults -n team-alpha -o yaml | grep -A5 resources
```

## Complete One-liner

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: team-alpha-limits
  namespace: team-alpha
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "2"
        memory: 4Gi
EOF
kubectl run test-defaults -n team-alpha --image=nginx:1.25 --restart=Never
```

## Key Concepts

1. **ResourceQuota**: Limits total resources a namespace can consume
2. **LimitRange**: Sets defaults and per-object limits
3. **Quota Enforcement**: Pods without resources specs are rejected unless LimitRange provides defaults
4. **Best Practice**: Always deploy LimitRange before ResourceQuota

## Verification Commands

```bash
kubectl describe quota team-alpha-quota -n team-alpha
kubectl describe limitrange team-alpha-limits -n team-alpha
kubectl get pod test-defaults -n team-alpha -o jsonpath='{.spec.containers[0].resources}'
```
