# Solution: Fix Broken Tekton Trigger

## Diagnosis with tkn CLI

First, inspect the resources:
```bash
tkn tt describe build-trigger-template -n cnpe-tekton-test
tkn tb describe build-trigger-binding -n cnpe-tekton-test
tkn pipeline list -n cnpe-tekton-test
```

## Phase 1: Fix TriggerTemplate

The TriggerTemplate references `build-application` but the pipeline is named `build-app`.

```bash
kubectl apply -f - <<'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: build-trigger-template
  namespace: cnpe-tekton-test
spec:
  params:
    - name: repo-url
      description: The git repository url
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: build-app-run-
      spec:
        pipelineRef:
          name: build-app
        params:
          - name: repo-url
            value: $(tt.params.repo-url)
EOF
```

## Phase 2: Fix TriggerBinding

The TriggerBinding has wrong param name (`git-url`) and wrong JSON path (`$(body.repo.url)`).

```bash
kubectl apply -f - <<'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: build-trigger-binding
  namespace: cnpe-tekton-test
spec:
  params:
    - name: repo-url
      value: $(body.repository.clone_url)
EOF
```

## Phase 3: Verify Configuration

Check that both resources are correctly configured:
```bash
# Verify TriggerTemplate
kubectl get triggertemplate build-trigger-template -n cnpe-tekton-test -o yaml

# Verify TriggerBinding
kubectl get triggerbinding build-trigger-binding -n cnpe-tekton-test -o yaml
```

The TriggerTemplate should reference `build-app` pipeline and TriggerBinding should extract `repo-url` from `$(body.repository.clone_url)`.

## Key Concepts

1. **TriggerTemplate** - Defines the resource (PipelineRun) to create when triggered
2. **TriggerBinding** - Extracts parameters from webhook payload using JSONPath
3. **Parameter flow**: TriggerBinding extracts data → TriggerTemplate creates PipelineRun with parameters

## Note on EventListeners

This exercise focuses on TriggerTemplate/TriggerBinding configuration. In production, you would add an EventListener to expose an HTTP endpoint for webhooks, but that requires additional Tekton Triggers infrastructure (core-interceptors).

## Reference: Useful tkn Commands

```bash
tkn tt list -n <namespace>        # List TriggerTemplates
tkn tb list -n <namespace>        # List TriggerBindings
tkn el list -n <namespace>        # List EventListeners
tkn pr list -n <namespace>        # List PipelineRuns
tkn pr logs --last -n <namespace> # View last PipelineRun logs
```
