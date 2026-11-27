# Create ApplicationSet for Environment Promotion

**Time:** 7 minutes
**Skills tested:** ArgoCD ApplicationSet, List Generator, Multi-environment deployment

## Context

The platform team needs to deploy the `demo-app` application across three environments: dev, staging, and production. Each environment has its own namespace already created. Instead of managing three separate Application resources, you should use an ApplicationSet to generate them automatically.

## Task

Create an ApplicationSet named `demo-app-set` in the `argocd` namespace that:

1. Uses a **Git generator** that discovers directories in a Git repository
2. Generates Applications named `demo-app-dev`, `demo-app-staging`, `demo-app-prod`
3. Deploys to namespaces `demo-dev`, `demo-staging`, `demo-prod` respectively
4. The Git repository should have a directory for each environment, and each directory should contain a `config.json` file with the environment name and namespace.
5. Enables automated sync with pruning and self-heal

## Requirements

- Generator must use the Git generator to discover directories
- The ApplicationSet should use the `config.json` file in each directory to parameterize the generated Applications.
- All three Applications must be created and syncing

## Verification

The exercise validates:
1. ApplicationSet exists with correct generator
2. Template uses proper parameter substitution
3. All three Applications are created

## Allowed Documentation

- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
