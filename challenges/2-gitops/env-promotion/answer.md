# Solution: Create ApplicationSet for Environment Promotion

## Create the ApplicationSet

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: demo-app-set
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: demo-dev
          - env: staging
            namespace: demo-staging
          - env: prod
            namespace: demo-prod
  template:
    metadata:
      name: 'demo-app-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: HEAD
        path: guestbook
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF
```

## Verification

```bash
# Check ApplicationSet
kubectl get applicationset demo-app-set -n argocd

# Check generated Applications
kubectl get applications -n argocd

# Should see:
# demo-app-dev
# demo-app-staging
# demo-app-prod
```

## Key Concepts

1. **ApplicationSet** - Generates multiple Applications from a single template
2. **List Generator** - Uses `elements` array to define parameter sets
3. **Template Parameters** - Use `{{paramName}}` syntax to reference generator values
4. **Automated Sync** - Enables continuous deployment with prune and self-heal

## Alternative: Using ArgoCD CLI

```bash
argocd appset create demo-app-set \
  --generator list \
  --list-element env=dev,namespace=demo-dev \
  --list-element env=staging,namespace=demo-staging \
  --list-element env=prod,namespace=demo-prod \
  --template-name 'demo-app-{{env}}' \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace '{{namespace}}'
```
