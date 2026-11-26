# Solution: Enforce a CI/CD Pipeline Security Scan Gate

## Diagnosis

```bash
kubectl get task security-scan -n cnpe-pipeline-sec -o yaml
kubectl get pipeline secure-release -n cnpe-pipeline-sec -o yaml
```

Two misconfigurations defeat the security gate:
1. `security-scan` sets `onError: continue` on step `scan-image`, so a non-zero exit code
   from the scanner still marks the TaskRun as succeeded.
2. `secure-release` sets `runAfter: ["build"]` on the `deploy` task, running deployment in
   parallel with `security-scan` instead of gating behind it.

## Fix the Security Gate

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: security-scan
  namespace: cnpe-pipeline-sec
spec:
  params:
    - name: image
      type: string
  steps:
    - name: scan-image
      image: alpine:3.19
      onError: stopAndFail
      script: |
        #!/bin/sh
        set -eu
        case "$(params.image)" in
          *:latest)
            echo "FAIL: mutable ':latest' tag is prohibited: $(params.image)" >&2
            exit 1
            ;;
          *:*)
            echo "PASS: pinned image tag verified: $(params.image)"
            ;;
          *)
            echo "FAIL: untagged image is prohibited: $(params.image)" >&2
            exit 1
            ;;
        esac
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: secure-release
  namespace: cnpe-pipeline-sec
spec:
  params:
    - name: image
      type: string
      default: "nginx:1.25"
  tasks:
    - name: build
      taskRef:
        name: build-image
      params:
        - name: image
          value: $(params.image)
    - name: security-scan
      taskRef:
        name: security-scan
      runAfter:
        - build
      params:
        - name: image
          value: $(params.image)
    - name: deploy
      taskRef:
        name: deploy-app
      runAfter:
        - security-scan
      params:
        - name: image
          value: $(params.image)
```

## Trigger the PipelineRun

```bash
kubectl delete pipelinerun secure-release-verify -n cnpe-pipeline-sec --ignore-not-found=true
kubectl apply -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: secure-release-verify
  namespace: cnpe-pipeline-sec
spec:
  pipelineRef:
    name: secure-release
  params:
    - name: image
      value: "nginx:1.25"
EOF
```

## Verification

```bash
kubectl get pipelinerun secure-release-verify -n cnpe-pipeline-sec
kubectl get taskruns -n cnpe-pipeline-sec
```

## Key Concepts

1. **Fail-closed pipeline gates**: `onError: continue` allows advisory steps to proceed on
   failure, which turns mandatory security checks into no-ops. Security gates must use
   `stopAndFail` (the Tekton default).
2. **Explicit DAG ordering**: Setting `runAfter: ["security-scan"]` on deployment tasks
   ensures Tekton skips `deploy` whenever the security check fails.
