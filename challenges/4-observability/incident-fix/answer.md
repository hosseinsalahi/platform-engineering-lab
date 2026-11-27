# Solution: Diagnose and Remediate Pod Failure

## Diagnosis Steps

```bash
# Check pod status
kubectl get pods -n cnpe-incident-test

# Check events for errors
kubectl describe pod -n cnpe-incident-test -l app=order-processor

# You'll see: Failed to pull image "nginx:99.99-nonexistent"
```

## Solution (kubectl edit - fastest)

```bash
kubectl edit deploy order-processor -n cnpe-incident-test
# Change image: nginx:99.99-nonexistent
# To:     image: nginx:1.25
```

## Solution (kubectl set image)

```bash
kubectl set image deploy/order-processor processor=nginx:1.25 -n cnpe-incident-test
```

## Solution (kubectl patch)

```bash
kubectl patch deploy order-processor -n cnpe-incident-test \
  --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.25"}]'
```

## Why This Matters

Incident diagnosis requires:
- **Systematic approach**: Events → Logs → Describe → Status
- **Pattern recognition**: ImagePullBackOff = image issue
- **Quick remediation**: Know fastest fix method for each issue type
