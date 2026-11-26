# Solution: Pod Disruption Budget

## What was wrong?

`web-pdb` existed, but its selector did not match the `web` Deployment pods, so it provided no disruption protection.

## Fix

Patch the PDB selector and ensure `minAvailable: 1`:

```bash
kubectl patch pdb web-pdb -n cnpe-pdb --type merge -p '
{
  "spec": {
    "minAvailable": 1,
    "selector": { "matchLabels": { "app": "web" } }
  }
}'
```

Verify:

```bash
kubectl get pdb web-pdb -n cnpe-pdb -o yaml
```

