# Answer: Fix OutOfSync ArgoCD Application

## What Was Broken

The Application `cnpe-broken-app` is misconfigured:
- **Wrong `spec.source.path`**: `guestbook-broken` (does not exist in repo)

## How to Diagnose
1. Check Application status:
   ```bash
   kubectl get app cnpe-broken-app -n argocd -o yaml
   ```
2. Look at sync status message - it will show path not found error
3. The Argo CD controller will also log an error about the invalid field.

## Solution
Edit the Application and fix the path:
```bash
kubectl patch app cnpe-broken-app -n argocd --type json -p='[{"op": "replace", "path": "/spec/source/path", "value": "guestbook"}]'
```
Or edit directly:
```bash
kubectl edit app cnpe-broken-app -n argocd
# Change: path: guestbook-broken
# To:     path: guestbook
```

## Alternative Valid Paths

The argocd-example-apps repo contains:
- `guestbook` (plain YAML)
- `helm-guestbook` (Helm chart)
- `kustomize-guestbook` (Kustomize)

Any of these would make the Application sync successfully.

## Why This Matters

Path errors are one of the most common GitOps issues:
- Typos in directory names
- Renamed folders in Git not updated in Application
- Branch merges changing structure

Always verify repo structure when debugging sync issues.
