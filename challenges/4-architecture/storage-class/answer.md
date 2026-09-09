# Solution: Configure StorageClass

## Important Note

StorageClass is immutable for reclaimPolicy and volumeBindingMode. You must delete and recreate it.

## Phase 1 & 2: Recreate StorageClass

```bash
# --ignore-not-found so this works whether or not the class already exists
kubectl delete storageclass fast-storage --ignore-not-found=true

kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-storage
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
EOF
```

## Phase 3: Create PVC

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-data
  namespace: cnpe-storage-test
spec:
  storageClassName: fast-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

## Complete One-liner

```bash
kubectl delete storageclass fast-storage && \
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-storage
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-data
  namespace: cnpe-storage-test
spec:
  storageClassName: fast-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

## Key Concepts

1. **Reclaim Policies**:
   - `Delete`: PV and data deleted when PVC released
   - `Retain`: PV persists, must be manually reclaimed
   - `Recycle`: Deprecated, don't use

2. **Volume Binding Modes**:
   - `Immediate`: PV provisioned when PVC created
   - `WaitForFirstConsumer`: PV provisioned when pod scheduled (respects topology)

3. **Why WaitForFirstConsumer**:
   - Ensures storage in same zone as pod
   - Required for topology-aware provisioning
   - Prevents cross-zone latency issues

## Verification Commands

```bash
kubectl get storageclass fast-storage -o yaml
kubectl get pvc -n cnpe-storage-test
kubectl describe pvc test-data -n cnpe-storage-test
```
