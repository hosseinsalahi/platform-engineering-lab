# Create CRD with Status Subresource

**Time:** 7 minutes
**Skills tested:** CustomResourceDefinition, Status Subresource, Controller Patterns

## Context

The platform team needs a `DatabaseClaim` CRD that allows developers to request database instances. The CRD must support status updates from controllers without triggering spec validation.

## Task

Create a CRD for `DatabaseClaim` in group `platform.cnpe.io`:

1. Create the CRD with proper schema for spec and status
2. Enable the status subresource for independent status updates
3. Create a DatabaseClaim instance and update its status

## Requirements

**CRD Specification:**
- Group: `platform.cnpe.io`, Version: `v1`
- Kind: `DatabaseClaim`, Plural: `databaseclaims`
- Namespaced scope
- Spec fields: `engine` (enum: postgres, mysql, mongodb), `size` (enum: small, medium, large)
- Status fields: `phase` (string), `conditions` (array)
- Status subresource enabled

**Instance:**
- Name: `test-db` in namespace `cnpe-crd-status-test`
- Engine: postgres, Size: medium
- Status phase: `Ready`

## Verification

The exercise validates:
1. CRD has status subresource enabled
2. Status schema includes phase and conditions
3. DatabaseClaim instance has Ready status

## Allowed Documentation

- [CRD Status Subresource](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#status-subresource)
- [API Conventions](https://kubernetes.io/docs/reference/using-api/api-concepts/)
