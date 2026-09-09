# Solution: Enforce Pod Security Standards

Two halves: label the namespace so the built-in Pod Security admission controller
enforces the `restricted` profile, then deploy a workload that actually satisfies it.

## Label the namespace

```bash
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted \
  --overwrite
```

`enforce` rejects violating pods, `warn` returns a message to the client, and `audit`
records an annotation in the audit log. Setting all three is the usual production
pattern: the same profile, three levels of feedback.

## Deploy a compliant workload

`restricted` demands every one of these — dropping any single field makes the pod
rejected at admission:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: production
  labels:
    app: api-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: api-server
        image: busybox:1.36
        command: ["sh", "-c", "sleep 3600"]
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop: ["ALL"]
          seccompProfile:
            type: RuntimeDefault
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 50m
            memory: 64Mi
```

Note the image choice: `restricted` forbids running as root, so an image whose default
user is root (stock `nginx`, for one) fails to start even with `runAsNonRoot: true` — the
kubelet refuses to run it. Pick an image that runs unprivileged, or set an explicit
`runAsUser`.

## Verification

```bash
kubectl get ns production --show-labels
kubectl rollout status deploy/api-server -n production
```

To see enforcement reject something, try a bare privileged pod:

```bash
kubectl run rejected --image=nginx -n production
```

## Key Concepts

1. **Three modes**: `enforce` blocks, `audit` records, `warn` messages the client. Roll a
   profile out as `warn`+`audit` first, then flip to `enforce`.
2. **Three profiles**: `privileged` (no restrictions), `baseline` (blocks known
   escalations), `restricted` (hardened — non-root, seccomp, no added capabilities).
3. **Pod Security is namespace-scoped and built in** — no webhook to install, unlike
   Kyverno or Gatekeeper, but also no cluster-wide policy and no exceptions mechanism.
