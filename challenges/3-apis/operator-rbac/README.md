# Troubleshoot Operator Not Reconciling

**Time:** 7 minutes
**Skills tested:** Operators, RBAC, Controller Troubleshooting

## Context

A custom operator has been deployed to manage DatabaseBackup resources, but it's not reconciling. The operator pod is running but nothing happens when you create a DatabaseBackup CR. You need to diagnose and fix the issue.

## Task

Fix the operator in `cnpe-operator-test` namespace:

1. Check operator pod logs for errors
2. Identify why reconciliation is failing
3. Fix the RBAC permissions
4. Verify the operator can now reconcile

## Hints

- Operators need RBAC permissions to watch/list/update resources
- Check ServiceAccount, Role, and RoleBinding
- Look for "forbidden" errors in operator logs
- Check the operator's deployment configuration for any namespace-related settings

## Verification

The exercise validates:
1. Role has correct permissions for databasebackups
2. RoleBinding connects role to service account
3. Operator can list the custom resources

## Allowed Documentation

- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
