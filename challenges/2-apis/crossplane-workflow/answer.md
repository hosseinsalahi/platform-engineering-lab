# Solution: Implement Self-Service Provisioning Workflow

## The API, the implementation, and the request

Three objects. The XRD defines the API developers get, the Composition says what the
platform builds when they use it, and the XR is a developer's actual request.

```bash
kubectl apply -f - <<'EOF'
# XRD - defines the self-service API.
# apiextensions.crossplane.io/v2 with scope: Namespaced is the current model:
# developers create the composite resource directly in their own namespace.
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: xdatabaserequests.platform.cnpe.io
spec:
  scope: Namespaced
  group: platform.cnpe.io
  names:
    kind: XDatabaseRequest
    plural: xdatabaserequests
  versions:
    - name: v1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                size:
                  type: string
                  enum: [small, medium, large]
                engine:
                  type: string
                  enum: [postgres, mysql]
              required: [size, engine]
---
# Composition - what the platform builds for that API.
# Composition is still apiextensions.crossplane.io/v1 in Crossplane 2.x.
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: database-composition
spec:
  mode: Pipeline
  compositeTypeRef:
    apiVersion: platform.cnpe.io/v1
    kind: XDatabaseRequest
  pipeline:
    - step: patch-and-transform
      functionRef:
        name: function-patch-and-transform
      input:
        apiVersion: pt.fn.crossplane.io/v1beta1
        kind: Resources
        resources:
          - name: connection-config
            base:
              apiVersion: kubernetes.crossplane.io/v1alpha2
              kind: Object
              spec:
                forProvider:
                  manifest:
                    apiVersion: v1
                    kind: ConfigMap
                    metadata:
                      namespace: cnpe-selfservice-test
                    data:
                      host: "db.internal"
                      port: "5432"
---
# A developer's request - a namespaced composite resource, created directly.
apiVersion: platform.cnpe.io/v1
kind: XDatabaseRequest
metadata:
  name: test-db
  namespace: cnpe-selfservice-test
spec:
  size: small
  engine: postgres
EOF
```

## What "Crossplane v2" actually changed

Worth separating two things that are easy to conflate, because they arrived years apart:

- **Composition pipeline mode** (`mode: Pipeline`, composition functions) landed in
  Crossplane 1.x. It replaced the old inline `spec.resources` array with a pipeline of
  functions that can transform, validate and generate resources, and chain together.
- **Crossplane v2** is the major release that changed the *resource model*. XRDs move to
  `apiextensions.crossplane.io/v2` and gain `spec.scope`. Composite resources can now be
  **namespaced**, and **claims are gone** — `claimNames` is not part of the v2 XRD API.

Under v1, an XR was cluster-scoped and developers interacted with a namespaced *claim*
that pointed at it — two kinds for one concept, which is what most of the confusion in
Crossplane v1 was about. In v2 the developer creates the namespaced XR itself.

v1 XRDs still work: they are treated as `scope: LegacyCluster`, which is cluster-scoped
with claim support. That is a compatibility path, not the pattern to build on.

## Why This Matters

Self-service provisioning enables:

- **Developer autonomy**: request resources without tickets
- **Standardization**: the platform controls what actually gets created
- **Guardrails**: the XRD schema rejects invalid input at the API, before anything is built
- **Abstraction**: one small API hides the infrastructure behind it

The XRD is the contract. Everything a developer can ask for, and everything they cannot,
is expressed in that schema — which is why `enum` on `size` and `engine` is doing more
work here than it looks.
