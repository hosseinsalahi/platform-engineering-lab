# Solution: Enforce Strict mTLS with Istio

The `payments` namespace has sidecar injection enabled but no workload and no mTLS
policy. Three objects are needed: the service to protect, a `PeerAuthentication` that
requires mTLS on the receiving side, and a `DestinationRule` that makes callers originate
it.

## Deploy the service

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: payments
  labels:
    app: payment-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-api
  template:
    metadata:
      labels:
        app: payment-api
    spec:
      containers:
      - name: payment-api
        image: hashicorp/http-echo
        args: ["-text=payments", "-listen=:8080"]
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
---
apiVersion: v1
kind: Service
metadata:
  name: payment-api
  namespace: payments
  labels:
    app: payment-api
spec:
  selector:
    app: payment-api
  ports:
  - name: http
    port: 80
    targetPort: 8080
```

The port is named `http` — Istio uses the port name (or `appProtocol`) to decide how to
proxy traffic, and an unnamed port falls back to plain TCP, losing L7 features.

## Require mTLS on the server side

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: payments
spec:
  mtls:
    mode: STRICT
```

Named `default` and given no `selector`, this applies to every workload in the namespace.
`STRICT` makes sidecars reject plaintext; the alternative, `PERMISSIVE`, accepts both and
is what you use while migrating.

## Originate mTLS on the client side

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: payment-api-mtls
  namespace: payments
spec:
  host: payment-api.payments.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

`ISTIO_MUTUAL` tells the client sidecar to use Istio's own certificates. Without it — with
mesh-wide auto-mTLS disabled — callers keep sending plaintext into a namespace that now
refuses it, and every request fails.

## Verification

```bash
kubectl get peerauthentication,destinationrule -n payments
istioctl x describe pod -n payments $(kubectl get pod -n payments -l app=payment-api -o jsonpath='{.items[0].metadata.name}')
```

## Key Concepts

1. **PeerAuthentication is server-side**, DestinationRule TLS is client-side. Strict mode
   without the matching client config breaks traffic.
2. **Scope**: a PeerAuthentication named `default` with no selector covers a namespace;
   in the root namespace (`istio-system`) it covers the mesh.
3. **Migration order**: `PERMISSIVE` everywhere, confirm all clients have sidecars, then
   move to `STRICT` — never the reverse.
