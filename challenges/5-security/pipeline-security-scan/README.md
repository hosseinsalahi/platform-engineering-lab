# Enforce a CI/CD Pipeline Security Scan Gate

**Time:** 8 minutes
**Skills tested:** Tekton Pipelines, Tekton Tasks, CI/CD supply-chain security gates

## Context

The platform team added an image provenance/tag check (`security-scan`) to the
`secure-release` Tekton Pipeline in namespace `cnpe-pipeline-sec`. However, unpinned
`:latest` images are still making it to the `deploy` task because:

1. The `security-scan` Task ignores step failures.
2. The `deploy` task in `secure-release` does not wait for `security-scan` to pass.

## Task

1. Update Task `security-scan` in `cnpe-pipeline-sec` so step `scan-image` uses
   `onError: stopAndFail`.
2. Update Pipeline `secure-release` in `cnpe-pipeline-sec` so task `deploy` has
   `runAfter: ["security-scan"]` instead of `["build"]`.
3. Create a `PipelineRun` named `secure-release-verify` in `cnpe-pipeline-sec` referencing
   Pipeline `secure-release` with parameter `image: "nginx:1.25"` and ensure it succeeds.

## Verification

The exercise validates:
1. Task `security-scan` does not set `onError: continue`.
2. Pipeline `secure-release` gates `deploy` behind `security-scan`.
3. `PipelineRun` `secure-release-verify` reaches `Succeeded=True`.

## Allowed Documentation

- [Tekton Pipelines](https://tekton.dev/docs/pipelines/pipelines/)
- [Tekton Tasks](https://tekton.dev/docs/pipelines/tasks/)
