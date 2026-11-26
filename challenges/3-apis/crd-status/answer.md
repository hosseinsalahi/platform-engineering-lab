# Solution: Add Status Subresource to CRD

## Phase 1 & 2: Fix CRD

```bash
kubectl edit crd databaseclaims.platform.cnpe.io
```

Add `subresources` and `status` schema under the version spec:

```yaml
versions:
  - name: v1
    served: true
    storage: true
    subresources:
      status: {}
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required:
              - engine
              - size
            properties:
              engine:
                type: string
                enum: ["postgres", "mysql", "mongodb"]
              size:
                type: string
                enum: ["small", "medium", "large"]
          status:
            type: object
            properties:
              phase:
                type: string
                enum: ["Pending", "Provisioning", "Ready", "Failed"]
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                      enum: ["True", "False", "Unknown"]
                    reason:
                      type: string
                    message:
                      type: string
                    lastTransitionTime:
                      type: string
                      format: date-time
```

## Phase 3: Create and Update Status

Create the DatabaseClaim:
```bash
kubectl apply -f - <<'EOF'
apiVersion: platform.cnpe.io/v1
kind: DatabaseClaim
metadata:
  name: test-db
  namespace: cnpe-crd-status-test
spec:
  engine: postgres
  size: medium
EOF
```

Update status using the status subresource:
```bash
kubectl patch databaseclaim test-db -n cnpe-crd-status-test \
  --type=merge --subresource=status \
  -p '{"status":{"phase":"Ready"}}'
```

## Complete One-liner

```bash
kubectl apply -f - <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databaseclaims.platform.cnpe.io
spec:
  group: platform.cnpe.io
  names:
    kind: DatabaseClaim
    listKind: DatabaseClaimList
    plural: databaseclaims
    singular: databaseclaim
    shortNames: [dbc]
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      subresources:
        status: {}
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [engine, size]
              properties:
                engine:
                  type: string
                  enum: [postgres, mysql, mongodb]
                size:
                  type: string
                  enum: [small, medium, large]
            status:
              type: object
              properties:
                phase:
                  type: string
                conditions:
                  type: array
                  items:
                    type: object
                    properties:
                      type: {type: string}
                      status: {type: string}
                      reason: {type: string}
                      message: {type: string}
                      lastTransitionTime: {type: string, format: date-time}
      additionalPrinterColumns:
        - {name: Engine, type: string, jsonPath: .spec.engine}
        - {name: Size, type: string, jsonPath: .spec.size}
        - {name: Phase, type: string, jsonPath: .status.phase}
        - {name: Age, type: date, jsonPath: .metadata.creationTimestamp}
EOF

kubectl apply -f - <<'EOF'
apiVersion: platform.cnpe.io/v1
kind: DatabaseClaim
metadata:
  name: test-db
  namespace: cnpe-crd-status-test
spec:
  engine: postgres
  size: medium
EOF

kubectl patch databaseclaim test-db -n cnpe-crd-status-test \
  --type=merge --subresource=status -p '{"status":{"phase":"Ready"}}'
```

## Key Concepts

1. **Status Subresource**: Enables `/status` endpoint for independent updates
2. **Why It Matters**: Controllers update status without spec validation, RBAC can be separated
3. **--subresource=status**: Required flag when patching status independently
4. **Conditions Pattern**: Standard way to report multiple statuses (Ready, Progressing, etc.)
