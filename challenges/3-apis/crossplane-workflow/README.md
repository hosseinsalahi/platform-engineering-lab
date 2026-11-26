# Implement Self-Service Provisioning Workflow

**Time:** 7 minutes
**Skills tested:** Self-Service APIs, Crossplane, Platform Automation

## Context

The platform team wants to enable self-service database provisioning. A developer should
be able to ask for a database by creating one small resource in their own namespace, and
the platform decides what actually gets built.

## Task

Create a self-service workflow in `cnpe-selfservice-test` namespace:

1. Create a **Crossplane Composition** that defines how to provision resources
2. Create a **CompositeResourceDefinition (XRD)** on `apiextensions.crossplane.io/v2`
   with `scope: Namespaced`, defining the `XDatabaseRequest` API
3. Create an **XDatabaseRequest** in `cnpe-selfservice-test` to exercise the API

Note: Crossplane v2 removed claims. Under v1 a developer used a namespaced *claim* that
pointed at a cluster-scoped composite; in v2 the composite itself is namespaced and is
created directly.

## Requirements

**XRD** (`xdatabaserequests.platform.cnpe.io`):
- Group: platform.cnpe.io
- Kind: XDatabaseRequest
- Claim kind: DatabaseRequest
- Properties: size (small/medium/large), engine (postgres/mysql)

**Composition** (`database-composition`):
- Composites: XDatabaseRequest
- Creates: ConfigMap with database connection info

## Verification

The exercise validates:
1. XRD exists and is established
2. Composition references correct composite type
3. DatabaseRequest claim can be created

## Allowed Documentation

- [Crossplane Compositions](https://docs.crossplane.io/latest/concepts/compositions/)
- [Composite Resource Definitions](https://docs.crossplane.io/latest/concepts/composite-resource-definitions-xrds/)
