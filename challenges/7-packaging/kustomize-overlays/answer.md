# Solution: Production Kustomize Overlay

## Reference: the finished overlay

`overlays/prod/kustomization.yaml` needs four things — the namespace, the name suffix,
the replica count, and a patch adding the memory limit:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: cnpe-packaging

resources:
- ../../base

nameSuffix: -prod

replicas:
- name: my-app
  count: 3

patches:
- target:
    kind: Deployment
    name: my-app
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/resources/limits
      value:
        memory: "512Mi"
```

Note that `replicas[].name` and the patch target both match the name in `base`
(`my-app`), not the suffixed result — `nameSuffix` is applied after these transformers.
The JSON 6902 patch uses `add` on `resources/limits` because `base` already defines
`resources.requests`; the parent object must exist for the path to resolve.

## Build and apply

This writes the overlay into a copy of the challenge tree so the repo's `overlays/prod`
stays in its unsolved state and the challenge can be run again:

```bash
cd "$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)"
cp -R challenges/7-packaging/kustomize-overlays "$WORK/kustomize"

cat > "$WORK/kustomize/overlays/prod/kustomization.yaml" <<'KUSTOMIZATION'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: cnpe-packaging

resources:
- ../../base

nameSuffix: -prod

replicas:
- name: my-app
  count: 3

patches:
- target:
    kind: Deployment
    name: my-app
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/resources/limits
      value:
        memory: "512Mi"
KUSTOMIZATION

kubectl kustomize "$WORK/kustomize/overlays/prod"
kubectl apply -k "$WORK/kustomize/overlays/prod"
```

To solve it in place instead, edit
`challenges/7-packaging/kustomize-overlays/overlays/prod/kustomization.yaml` directly and
run `kubectl apply -k challenges/7-packaging/kustomize-overlays/overlays/prod`, then
`git checkout` the file to restore the TODO stub.

## Verification

```bash
kubectl get deploy my-app-prod -n cnpe-packaging -o yaml
```

Expect `replicas: 3` and a `512Mi` memory limit on the `app` container.

## Key Concepts

1. **`nameSuffix`/`namePrefix`** rewrite resource names and every reference to them, so
   overlays never collide with the base.
2. **`replicas:`** is a built-in transformer — cleaner than patching `/spec/replicas` by
   hand for the common case.
3. **`patches:`** accepts both strategic-merge and JSON 6902 patches; the `target`
   selector decides which resources a patch applies to.
