# Configure StorageClass for Stateful Workloads

**Time:** 7 minutes
**Skills tested:** StorageClass, Persistent Volumes, Storage Policies

## Context

The platform team needs to provide storage for stateful applications. You must create a StorageClass with appropriate retention and binding policies for production workloads.

## Task

Configure storage for the `cnpe-storage-test` namespace:

1. Create a **StorageClass** with production-safe settings
2. Create a **PersistentVolumeClaim** using the StorageClass
3. Verify the PVC is created correctly

## Requirements

**StorageClass** (`fast-storage`):
- Provisioner: `rancher.io/local-path` (kind cluster compatible)
- Reclaim policy: `Retain` (preserve data on PVC deletion)
- Volume binding mode: `WaitForFirstConsumer` (topology-aware)

**PersistentVolumeClaim** (`test-data`):
- Namespace: cnpe-storage-test
- Storage class: fast-storage
- Access mode: ReadWriteOnce
- Size: 1Gi

## Verification

The exercise validates:
1. StorageClass has Retain reclaim policy
2. StorageClass has WaitForFirstConsumer binding mode
3. PVC exists with correct StorageClass reference

## Allowed Documentation

- [StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
