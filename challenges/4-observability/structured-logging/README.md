# Configure Sidecar Logging and Log Scraping Annotations

**Time:** 7 minutes
**Skills tested:** Kubernetes logging architecture, sidecar containers, pod annotations

## Context

The `checkout-worker` Deployment in namespace `cnpe-logging` writes structured JSON logs to
`/var/log/app/app.log` on a shared `emptyDir` volume. The cluster log shipper only collects
container `stdout`/`stderr` and expects pod annotations indicating opt-in scraping and JSON
parsing.

Right now, the `log-streamer` sidecar is failing to read the log file and log collection is
disabled on the pod template.

## Task

1. Update the `checkout-worker` Deployment pod template annotations in `cnpe-logging`:
   - `logging.cnpe.io/scrape: "true"`
   - `logging.cnpe.io/format: "json"`
2. Fix the `log-streamer` container's `varlog` `volumeMount` so it mounts at `/var/log/app`.
3. Verify the rollout succeeds and `log-streamer` emits the structured JSON log lines.

## Verification

The exercise validates:
1. Pod template annotations are set to `logging.cnpe.io/scrape: "true"` and `logging.cnpe.io/format: "json"`.
2. The `log-streamer` sidecar mounts `varlog` at `/var/log/app` and the Deployment is available.
3. Structured JSON logs containing `"service":"checkout"` appear in `kubectl logs` for `log-streamer`.

## Allowed Documentation

- [Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
- [kubectl logs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/)
