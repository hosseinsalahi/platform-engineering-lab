# Platform Engineer Battleground

[![Preflight](https://github.com/Liquid-Reply/platform-engineer-battleground/actions/workflows/preflight.yml/badge.svg)](https://github.com/Liquid-Reply/platform-engineer-battleground/actions/workflows/preflight.yml)

Hands-on challenges for mastering cloud-native platform engineering. Battle-tested scenarios using progressive testing with [KUTTL](https://kuttl.dev/).

## What is This?

A practical training ground for platform engineers. Real-world challenges covering GitOps workflows, canary deployments, policy enforcement, and observability on actual Kubernetes clusters.

## Quick Start

```bash
just provision          # kind cluster + all platform tools (~10-15 min)
# or: just provision-exam exams/exam-1.yaml  # install only tools needed for an exam
# or: just provision-minimal                     # kind cluster only
just gitops-fix     # run a challenge
just destroy        # cleanup
just check          # verify required tooling
just preflight      # validate challenges & asserts
just check-docs     # verify markdown links
just lint-sh        # shellcheck scripts (devbox provides it)
```

Note: some runners generate a local `kubeconfig` file in the repo root; it is intentionally ignored by git.

## Cluster Configuration

- **Kubernetes Version**: v1.35.0 (via kind)
- **Nodes**: 1 control-plane + 2 workers
- **Container Engine**: Podman
- **Container Runtime**: Containerd
- **Orchestrator**: Kind

## Prerequisites

**Required**:
- Podman, kind, kubectl, helm, [kuttl](https://kuttl.dev/docs/cli.html)
  - KUTTL must be installed as the kubectl plugin so `kubectl kuttl` works
  - Python 3 with PyYAML for helper output in the runner (`pip install pyyaml`)
  - **macOS with Apple Silicon**: Podman machine must be initialized and running (see installation instructions below)

If you want a lighter cluster, use `just provision-exam <exam.yaml>` (installs only the components required for that exam) or `just provision-minimal` (cluster only).

**Optional** CLI tools via devbox:
```bash
devbox shell  # argocd, tkn, kyverno, istioctl
```
Or install `yq` locally, which is recommended for YAML parsing in tooling.

## CLI Install (if not using devbox)

macOS (Homebrew):
```bash
brew install kuttl kind kubernetes-cli helm istioctl tektoncd-cli argocd kyverno yq
python3 -m pip install --user pyyaml
```

Ubuntu/Debian (examples):
```bash
sudo apt-get update && sudo apt-get install -y podman
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
brew install helm || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
python3 -m pip install --user kuttl pyyaml
# Configure kind to use podman
export KIND_EXPERIMENTAL_PROVIDER=podman
```

Tip: `just check` will confirm everything is available.

### macOS Podman Setup (Required for Apple Silicon)

On macOS, especially with Apple Silicon chips, Podman requires a Podman machine:

```bash
# Install podman via Homebrew
brew install podman

# Initialize Podman machine with recommended resources
# Recommended: 4-6 CPUs, 8-12GB RAM, 50GB disk for running all platform tools
podman machine init --cpus 4 --memory 8192 --disk-size 50

# Start Podman machine
podman machine start

# Configure kind to use podman
export KIND_EXPERIMENTAL_PROVIDER=podman

# Optional: Add to your shell profile (~/.zshrc or ~/.bash_profile)
echo 'export KIND_EXPERIMENTAL_PROVIDER=podman' >> ~/.zshrc
```

**Resource Requirements:**
- **Minimum**: 4 CPUs, 8GB RAM, 50GB disk
- **Recommended**: 6 CPUs, 12GB RAM, 100GB disk (for smoother operation with all components)

**Note**: The cluster installs ArgoCD, Argo Rollouts, Tekton, Kyverno, Gatekeeper, External Secrets, Prometheus, Grafana, Jaeger, Istio, Crossplane, and OpenCost.

Verify Podman is running:
```bash
podman machine list  # Should show a running machine
podman ps           # Should connect without errors
```

To install CLIs via Homebrew on macOS using a single command:
```bash
just install-cli
```

On Linux, either print or apply recommended install commands:
```bash
# Print commands for your distro
just install-cli --print

# Apply commands (uses sudo for installs)
just install-cli --apply
```

Upgrade the CLI tools later with:
```bash
just upgrade-cli
```

## CI

Every PR runs a preflight validation in GitHub Actions to ensure all challenge setups and asserts are valid:
```bash
python3 scripts/preflight.py
```
See `.github/workflows/preflight.yml`.

## Installed Components

The provisioning script installs these platform engineering tools:

| Category | Tool |
|----------|------|
| GitOps | ArgoCD |
| Progressive Delivery | Argo Rollouts |
| CI/CD | Tekton |
| Policy | Kyverno, Gatekeeper |
| Secrets | External Secrets |
| Observability | Prometheus, Grafana |
| Tracing | Jaeger |
| Service Mesh | Istio |
| Cost | OpenCost |
| Infrastructure | Crossplane |

## Challenges

32 challenges across 7 domains. See [docs/SOLUTIONS.md](docs/SOLUTIONS.md) for concepts and answers.

### 1: GitOps and Continuous Delivery (25%)
- **broken-sync**: Diagnose and fix an Argo CD application that is out of sync.
- **canary-rollout**: Migrate a Kubernetes Deployment to an Argo Rollout for canary releases.
- **tekton-pipeline**: Troubleshoot a Tekton Trigger that is failing to create PipelineRuns.
- **env-promotion**: Use an Argo CD ApplicationSet to manage an application across multiple environments.
- **bluegreen**: Perform a blue-green deployment using Argo Rollouts.
- **istio-canary**: Troubleshoot a canary release that is failing due to an Istio misconfiguration.

### 2: Platform APIs and Self-Service (25%)
- **platform-crd**: Create a CustomResourceDefinition to enable self-service environment provisioning.
- **crd-status**: Add a status subresource to a CustomResourceDefinition.
- **operator-rbac**: Troubleshoot a Kubernetes operator that is not reconciling.
- **crossplane-workflow**: Create a self-service workflow using Crossplane.

### 3: Observability and Operations (20%)
- **broken-servicemonitor**: Fix a ServiceMonitor selector so Prometheus scrapes the target.
- **cost-allocation**: Configure OpenCost for cost allocation.
- **grafana-dashboard**: Troubleshoot a broken Grafana dashboard.
- **prometheus-alert**: Create a Prometheus alerting rule.
- **jaeger-trace**: Trace a request through a microservices application using Jaeger.
- **incident-fix**: Diagnose and fix a failing application using observability tools.

### 4: Platform Architecture (15%)
- **network-policy**: Configure NetworkPolicies for a multi-tenant environment.
- **resource-quota**: Configure ResourceQuotas and LimitRanges for a multi-tenant environment.
- **pod-disruption-budget**: Fix a PodDisruptionBudget selector to prevent downtime during maintenance.
- **storage-class**: Configure a StorageClass for stateful workloads.
- **service-mesh**: Configure Istio for traffic splitting.
- **istio-fault-injection**: Inject faults with an Istio VirtualService to test resilience.

### 5: Security and Policy Enforcement (15%)
- **kyverno-policy**: Troubleshoot a broken Kyverno policy.
- **rbac-fix**: Troubleshoot an RBAC issue.
- **rbac-minimal**: Grant least-privilege RBAC (ConfigMaps allowed, Secrets denied).
- **pod-security**: Enforce Pod Security Standards.
- **istio-mtls**: Configure strict mTLS with Istio.
- **gatekeeper-constraint**: Create a Gatekeeper Constraint to enforce a policy.
- **external-secrets**: Fix a broken ExternalSecret so the Secret syncs from the store.

### 6: Scalability (Bonus)
- **hpa-cpu**: Configure Horizontal Pod Autoscaling based on CPU.

### 7: Packaging (Bonus)
- **helm-templating**: Fix a broken Helm chart.
- **kustomize-overlays**: Create a production Kustomize overlay.

```bash
just domain-gitops        # or: just gitops-fix, just gitops-canary, ...
just domain-platform
just domain-observability
just domain-architecture
just domain-security
just domain-scalability
just domain-packaging
```

## How KUTTL Progressive Testing Works

[KUTTL](https://kuttl.dev/) creates **progressive, multi-step challenges** that simulate real platform engineering scenarios.

### Challenge Structure

```
challenges/1-gitops/broken-sync/
├── setup.yaml      # Creates the broken state (runs first)
├── 00-assert.yaml  # Step 1: waits for initial fix
├── 01-assert.yaml  # Step 2: validates additional requirements
├── steps.txt       # Hints (format: "0:First step description")
├── answer.md       # Solution - try without peeking!
└── README.md       # Challenge description, docs links
```

### How It Works

1. **Setup Phase**: KUTTL applies `setup.yaml` to create a broken resource
2. **Assertion Phase**: KUTTL waits for conditions to become true. You fix the issue in another terminal.
3. **Timer**: 7-minute timeout simulates real incident response
4. **Auto-Cleanup**: Resources deleted automatically when test completes

### During the Challenge

- **Split your terminal**: Run KUTTL in one pane, fix issues in another
- **Use the docs**: Each challenge README links to relevant documentation
- **Check steps.txt**: Hints available if stuck

## Relationship to the CNPA Certification

This repo is a **hands-on lab**, not an exam simulator. It is worth being precise about
that, because the two are different things.

The relevant certification is the CNCF/Linux Foundation
[Certified Cloud Native Platform Engineering Associate (CNPA)](https://www.cncf.io/training/certification/cnpa/),
which is an online, proctored, **multiple-choice** exam — there is no practical component
to simulate. Working through these challenges is a good way to *understand* the material;
it is not a mock exam, and the per-challenge timer here is a focus device, not a
reproduction of exam conditions.

CNPA's published domains, and where this repo lands against them:

| CNPA domain | Weight | Covered here |
|---|---|---|
| Platform Engineering Core Fundamentals | 36% | Partially — `4-architecture`, `6-scalability`, `7-packaging` cover the practical side; the conceptual material is not exercised |
| Platform Observability, Security and Conformance | 20% | Yes — `3-observability` and `5-security` |
| Continuous Delivery & Platform Engineering | 16% | Yes — `1-gitops` |
| Platform APIs and Provisioning Infrastructure | 12% | Yes — `2-apis` |
| IDPs and Developer Experience | 8% | **No challenges** |
| Measuring your Platform | 8% | **No challenges** |

So roughly 16% of the exam has no challenge here at all, and the largest domain is only
partly exercised. If you are preparing for CNPA, use this alongside the official
curriculum rather than instead of it.

The seven directories under `challenges/` are organised by practical subject, not by CNPA
weighting — they are sized by what makes a good hands-on scenario.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the challenge layout,
the `answer.md` contract used by `just solve`, and the checks CI runs.
