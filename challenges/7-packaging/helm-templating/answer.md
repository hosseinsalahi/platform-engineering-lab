# Solution: Fix Broken Helm Chart

## Diagnosis

```bash
helm template challenges/7-packaging/helm-templating/chart --debug
```

Rendering fails with `nil pointer evaluating interface {}` because two template
expressions reference values that do not exist.

**Error 1** — `templates/deployment.yaml` uses `{{ .Values.replicas }}`, but the key in
`values.yaml` is `replicaCount`:

```
replicas: {{ .Values.replicas }}      ->  replicas: {{ .Values.replicaCount }}
```

**Error 2** — the same file uses `.Value.image.pullPolicy`; the built-in object is
`.Values` (plural):

```
imagePullPolicy: {{ .Value.image.pullPolicy }}  ->  imagePullPolicy: {{ .Values.image.pullPolicy }}
```

## Fix and install

The chart under `challenges/` is the broken starting state, so this copies it to a
scratch directory, applies both corrections there, and installs from the copy. The
challenge therefore stays re-runnable.

```bash
cd "$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)"
cp -R challenges/7-packaging/helm-templating/chart "$WORK/chart"

cat > "$WORK/chart/templates/deployment.yaml" <<'CHART'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
        - name: web-app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
CHART

helm template "$WORK/chart" >/dev/null
helm upgrade --install web-app "$WORK/chart" -n cnpe-packaging --wait --timeout 3m
```

If you prefer to edit in place, change the two expressions in
`challenges/7-packaging/helm-templating/chart/templates/deployment.yaml` and run
`helm upgrade --install web-app ./chart -n cnpe-packaging` from the challenge
directory — then `git checkout` the chart afterwards to restore the broken state.

## Verification

```bash
kubectl get deploy web-app -n cnpe-packaging -o yaml
```

The Deployment should have 2 replicas, image `nginx:1.19`, and
`imagePullPolicy: IfNotPresent`, all sourced from `values.yaml`.
