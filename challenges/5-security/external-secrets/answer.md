# Solution: Fix Broken External Secret Sync

## Diagnosis

```bash
kubectl describe externalsecret payment-db-secret -n cnpe-eso-test
```

The `Ready` condition is `False` with reason `SecretSyncedError`, and the event names the
failing entry:

```
error processing spec.data[1] (key: /prod/payment-service/db), err: ... pass_word
```

The store holds a JSON document with the keys `username`, `password`, and `host`. The
ExternalSecret asks for the property `pass_word`, which does not exist, so ESO refuses to
write any part of the target Secret — one bad entry fails the whole sync.

## Fix the property name

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: payment-db-secret
  namespace: cnpe-eso-test
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: global-fake-store
    kind: ClusterSecretStore
  target:
    name: payment-db-connection
    creationPolicy: Owner
  data:
  - secretKey: DB_HOST
    remoteRef:
      key: "/prod/payment-service/db"
      property: "host"
  - secretKey: DB_PASSWORD
    remoteRef:
      key: "/prod/payment-service/db"
      property: "password"
```

Editing the live object works too: `kubectl edit externalsecret payment-db-secret -n
cnpe-eso-test` and change `pass_word` to `password`.

## Verification

```bash
kubectl get externalsecret payment-db-secret -n cnpe-eso-test
kubectl get secret payment-db-connection -n cnpe-eso-test -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

The ExternalSecret reports `SecretSynced`, and the Secret contains the decoded password.

## Key Concepts

1. **`remoteRef.property`** selects a field out of a structured (JSON) value; without it
   the whole value lands in the key.
2. **A single bad entry fails the whole ExternalSecret** — ESO writes the target Secret
   atomically rather than partially.
3. **`creationPolicy: Owner`** makes ESO own the Secret, so deleting the ExternalSecret
   garbage-collects it.
4. **`refreshInterval`** controls re-read cadence; a fix is picked up on the next
   reconcile, not only at the interval.
