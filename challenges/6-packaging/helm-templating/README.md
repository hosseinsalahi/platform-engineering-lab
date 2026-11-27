# Fix Broken Helm Chart

**Time:** 7 minutes
**Skills tested:** Helm, Go Templates, Debugging

## Context

A developer created a Helm chart for the `web-app` service, but it fails to render.
The deployment pipeline is blocked. You need to identify the syntax errors in the template and fix them.

## Task

1.  Navigate to the `challenges/6-packaging/helm-templating/chart` directory (or edit files directly).
2.  Debug the template issues using `helm template . --debug`.
3.  Fix the syntax errors in `templates/deployment.yaml`.
4.  Install the chart to the `cnpe-packaging` namespace using:
    ```bash
    helm install web-app ./chart -n cnpe-packaging
    ```

## Verification

The exercise validates:
1.  Deployment `web-app` exists in `cnpe-packaging`.
2.  Deployment has correct image tag (from values).
3.  Deployment has correct replica count (from values).

## Allowed Documentation

- [Helm Chart Template Guide](https://helm.sh/docs/chart_template_guide/)
