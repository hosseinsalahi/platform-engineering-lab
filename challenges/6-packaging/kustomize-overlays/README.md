# Create Production Kustomize Overlay

**Time:** 7 minutes
**Skills tested:** Kustomize, Overlays, Patching

## Context

The `base` directory contains the definition for a simple application.
We need to deploy this application to production with different configurations.

## Task

Create a Kustomize overlay in `challenges/6-packaging/kustomize-overlays/overlays/prod` that:
1.  Inherits from `../../base`.
2.  Updates the replica count to **3**.
3.  Sets a resource limit of **512Mi** memory for the container.
4.  Adds the suffix `-prod` to all resource names.
5.  Deploys to the namespace `cnpe-packaging`.

Apply your configuration using:
```bash
kubectl apply -k challenges/6-packaging/kustomize-overlays/overlays/prod
```

## Verification

The exercise validates:
1.  Deployment `my-app-prod` exists in `cnpe-packaging`.
2.  Deployment has 3 replicas.
3.  Container has memory limit `512Mi`.

## Allowed Documentation

- [Kustomize Overlays](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/)
