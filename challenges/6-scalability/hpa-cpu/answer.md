# Solution: Horizontal Pod Autoscaling on CPU

The Deployment `php-apache` already exists in `cnpe-scaling`. Create an HPA that targets
it, scaling between 2 and 10 replicas at 50% average CPU.

## Create the HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache-hpa
  namespace: cnpe-scaling
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
```

Save it as `hpa.yaml` and `kubectl apply -f hpa.yaml`, or pipe it straight to
`kubectl apply -f -`.

## Alternative: the imperative form

`kubectl autoscale` produces an equivalent HPA, but names it after the Deployment
(`php-apache`), not `php-apache-hpa`. The assert checks for `php-apache-hpa`, so rename
it or use the manifest above.

```bash
kubectl autoscale deployment php-apache --cpu-percent=50 --min=2 --max=10 -n cnpe-scaling
```

## Verification

```bash
kubectl get hpa php-apache-hpa -n cnpe-scaling
```

`TARGETS` shows `<unknown>` until metrics-server has scraped the pods; the assert only
checks the HPA spec, not live metrics.

## Key Concepts

1. **targetCPUUtilizationPercentage** is a percentage of the pod's CPU *request*, not of
   a core — so the Deployment must set `resources.requests.cpu` for the HPA to compute a
   ratio.
2. **autoscaling/v1** carries only CPU targets; `autoscaling/v2` adds memory, custom, and
   external metrics.
3. `minReplicas` raises the floor: the Deployment's own `replicas: 1` is overridden once
   the HPA takes ownership of scaling.
