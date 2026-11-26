# Solution: Create Platform CRD

## Fastest Method (kubectl edit)

### Step 1: Fix the CRD
```bash
kubectl edit crd environments.platform.cnpe.io
```

Find the `spec` properties section and update to:
```yaml
spec:
  type: object
  required:        # <-- add this
  - team
  - size
  properties:
    team:
      type: string
    size:
      type: string
      enum:          # <-- add this
      - small
      - medium
      - large
```

### Step 2: Create the Environment CR
```bash
kubectl apply -f - <<EOF
apiVersion: platform.cnpe.io/v1
kind: Environment
metadata:
  name: dev-alpha
  namespace: cnpe-platform
spec:
  team: alpha
  size: medium
EOF
```

## Alternative: Full CRD replacement

```bash
kubectl apply -f - <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: environments.platform.cnpe.io
spec:
  group: platform.cnpe.io
  names:
    kind: Environment
    listKind: EnvironmentList
    plural: environments
    singular: environment
    shortNames:
    - env
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required:
            - team
            - size
            properties:
              team:
                type: string
              size:
                type: string
                enum:
                - small
                - medium
                - large
    additionalPrinterColumns:
    - name: Team
      type: string
      jsonPath: .spec.team
    - name: Size
      type: string
      jsonPath: .spec.size
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
EOF
```

## Verify

```bash
# Check CRD is ready
kubectl get crd environments.platform.cnpe.io

# Try creating with invalid size (should fail)
kubectl apply -f - <<EOF
apiVersion: platform.cnpe.io/v1
kind: Environment
metadata:
  name: test-invalid
  namespace: cnpe-platform
spec:
  team: test
  size: xlarge  # Invalid - should fail
EOF

# List environments
kubectl get env -n cnpe-platform
```

## Why This Matters

CRDs enable self-service by:
- Allowing developers to request resources declaratively
- Enforcing validation (required fields, enums) at API level
- Enabling GitOps workflows for platform requests
- Decoupling request from fulfillment (controller handles provisioning)
