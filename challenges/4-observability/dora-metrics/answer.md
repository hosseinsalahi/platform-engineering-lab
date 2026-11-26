# Solution: Make the DORA Recording Rules Load

## Diagnosis

```bash
kubectl get prometheusrule platform-dora-metrics -n monitoring -o yaml
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
```

The Prometheus object created by kube-prometheus-stack selects rules with
`release: prometheus-stack`. Our object carries only `app: platform-metrics`, so the
operator never includes it in the generated rule files. The object is perfectly valid and
completely inert — there is no error anywhere, which is what makes this one slow to spot.

The second problem appears once the rule is actually read: `platform/deployment_frequency:1h`
is not a valid metric name. Recording rule names must match the metric-name grammar;
colons are conventional for recording rules, slashes are not allowed.

## Apply the corrected rule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: platform-dora-metrics
  namespace: monitoring
  labels:
    app: platform-metrics
    release: prometheus-stack
spec:
  groups:
    - name: platform.dora
      interval: 30s
      rules:
        - record: platform:deployment_frequency:1h
          expr: sum(changes(kube_deployment_status_observed_generation[1h]))
        - record: platform:change_failure_ratio:1h
          expr: |
            sum(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"})
            /
            clamp_min(sum(kube_pod_status_phase{phase="Running"}), 1)
```

`clamp_min(..., 1)` keeps the ratio defined on an idle cluster instead of dividing by
zero.

## Verification

```bash
kubectl get --raw \
  "/api/v1/namespaces/monitoring/services/prometheus-stack-kube-prom-prometheus:9090/proxy/api/v1/rules" \
  | grep platform.dora
```

The Prometheus image ships without a shell's worth of tools — no `wget`, no `curl` — so
`kubectl exec` is not an option here. Going through the API server's service proxy needs
neither a port-forward nor anything installed in the container.

The operator writes the rule file and signals a reload, so this can take a few tens of
seconds after the apply. Checking Prometheus's own rules API is the only check that
proves the pipeline works end to end — the object existing proves nothing.

## Key Concepts

1. **Selector-based discovery is silent when it misses.** `ruleSelector`,
   `serviceMonitorSelector` and friends match on labels; an object that does not match is
   not an error, it simply does not exist as far as Prometheus is concerned. The same
   failure shape appears in the `broken-servicemonitor` challenge.
2. **Recording rules pre-compute expensive queries** at evaluation time, so dashboards
   read one cheap series instead of re-running an aggregation over hours of data. Name
   them `level:metric:operation`.
3. **Measuring the platform is a platform responsibility.** DORA's four keys —
   deployment frequency, lead time, change failure rate, time to restore — are only
   partly visible from cluster state. Deploy events and incident timings come from the
   delivery pipeline and the on-call system, and a platform team that wants the numbers
   has to instrument those too.
