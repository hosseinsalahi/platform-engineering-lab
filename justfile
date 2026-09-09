set export

# Configure kind to use Podman (required for Podman users)
export KIND_EXPERIMENTAL_PROVIDER := env_var_or_default('KIND_EXPERIMENTAL_PROVIDER', 'podman')

# Kind cluster name used by this repo (kube context becomes `kind-<name>`)
export CNPE_CLUSTER_NAME := env_var_or_default('CNPE_CLUSTER_NAME', 'battleground')

# Show available recipes
default:
  just --list

# Verify that key CLIs respond to `--help`
help-check:
  bash ./scripts/help-check.sh

# ==================== Cluster Provisioning ====================

# Provision Platform Battleground cluster (kind + all tools)
provision *ARGS:
  ./scripts/provision-cluster.sh {{ARGS}}

# Provision minimal cluster (kind only, no platform tools)
provision-minimal:
  ./scripts/provision-cluster.sh --minimal

# Provision cluster with only the tools needed for an exam YAML
provision-exam *ARGS:
  @bash -c 'set -- {{ARGS}}; for a in "$@"; do case "$a" in -h|--help) set -- --help; break ;; esac; done; case "${1:-}" in ""|--help|-h) \
    echo "Usage: just provision-exam <exam>"; \
    echo ""; \
    echo "Provisions a local cluster (if needed) and installs only the tools required for an exam."; \
    echo ""; \
    echo "Examples:"; \
    echo "  just provision-exam exam-1"; \
    echo "  just provision-exam 2"; \
    echo "  just provision-exam domain-gitops"; \
    echo ""; \
    echo "Notes:"; \
    echo "  - Override cluster name: CNPE_CLUSTER_NAME=mycluster just provision-exam exam-1"; \
    exit 0 ;; \
    -*) ./scripts/provision-cluster-light.sh "$@" ;; \
    *) exam="$1"; shift; ./scripts/provision-cluster-light.sh --exam "$exam" "$@" ;; \
  esac'

# Provision cluster with an explicit tool list
provision-tools *ARGS:
  @bash -c 'set -- {{ARGS}}; for a in "$@"; do case "$a" in -h|--help) set -- --help; break ;; esac; done; case "${1:-}" in ""|--help|-h) \
    echo "Usage: just provision-tools <tool-list>"; \
    echo ""; \
    echo "Provisions a local cluster (if needed) and installs only the selected tools."; \
    echo ""; \
    echo "Example:"; \
    echo "  just provision-tools argocd,argo-rollouts,prometheus-stack"; \
    echo ""; \
    echo "Notes:"; \
    echo "  - Override cluster name: CNPE_CLUSTER_NAME=mycluster just provision-tools argocd"; \
    exit 0 ;; \
    -*) ./scripts/provision-cluster-light.sh "$@" ;; \
    *) tools="$1"; shift; ./scripts/provision-cluster-light.sh --tools "$tools" "$@" ;; \
  esac'

# Print which tools an exam needs (for selective setup)
# - `just exam-tools exams/mock-exam-1.yaml`
# - `just exam-tools --help`
exam-tools *ARGS:
  @bash -c 'set -- {{ARGS}}; for a in "$@"; do case "$a" in -h|--help) set -- --help; break ;; esac; done; case "${1:-}" in ""|--help|-h) \
    echo "Usage: just exam-tools <exam> [--format csv|lines]"; \
    echo ""; \
    echo "Prints the list of tools required for an exam."; \
    echo ""; \
    echo "Examples:"; \
    echo "  just exam-tools exam-2"; \
    echo "  just exam-tools domain-gitops --format csv"; \
    exit 0 ;; \
    -* ) exec python3 ./scripts/exam-tools.py "$@" ;; \
    * ) exam="$1"; shift; exec python3 ./scripts/exam-tools.py --exam "$exam" "$@" ;; \
  esac'

# Teardown cluster
destroy:
  kind delete cluster --name "{{CNPE_CLUSTER_NAME}}"

# Verify required tools are installed
check *ARGS:
  ./scripts/check.sh {{ARGS}}

# Install developer CLIs (macOS Homebrew)
install-cli *ARGS:
  bash ./scripts/install-cli.sh {{ARGS}}

# Upgrade developer CLIs
upgrade-cli *ARGS:
  bash ./scripts/upgrade-cli.sh {{ARGS}}

# Preflight validation for exercises
preflight *ARGS:
  python3 ./scripts/preflight.py {{ARGS}}

# Check markdown docs for broken relative links
check-docs *ARGS:
  python3 ./scripts/check-md-links.py {{ARGS}}

# Lint shell scripts (requires shellcheck)
lint-sh:
  shellcheck -x scripts/*.sh

# ==================== Exams ====================

# List available exams
exams:
  @echo "Exams:"
  @ls -1 exams/*.yaml | sed 's|^exams/||; s|\.yaml$||; s|^|  - |'

# Run an exam by name (e.g. exam-1, domain-gitops)
exam name *ARGS:
  @bash -c 'if [[ "{{name}}" == "-h" || "{{name}}" == "--help" ]]; then set -- --help; else set -- {{ARGS}}; fi; \
    for a in "$@"; do case "$a" in -h|--help) set -- --help; break ;; esac; done; \
    case "${1:-}" in -h|--help) \
      echo "Usage: just exam <exam> [options] [start|list]"; \
      echo ""; \
      echo "Examples:"; \
      echo "  just exam exam-1"; \
      echo "  just exam exam-2 list"; \
      echo "  just exam domain-gitops"; \
      echo ""; \
      echo "Notes:"; \
      echo "  - Override cluster name: CNPE_CLUSTER_NAME=mycluster just exam exam-1"; \
      exit 0 ;; \
    esac; \
    if [[ $# -eq 0 ]]; then set -- start; fi; \
    exec ./scripts/run-exam.sh "$@" "{{name}}"'

# Run exam 1 (interactive)
exam-1 *ARGS:
  @just exam exam-1 {{ARGS}}

# Run exam 2 (interactive)
exam-2 *ARGS:
  @just exam exam-2 {{ARGS}}

# ==================== Auto-Solve ====================

# Auto-solve a challenge or an exam YAML
# - `just solve 4-architecture/network-policy`
# - `just solve exam-1`
# - `just solve --help`
solve *ARGS:
  @python3 ./scripts/solve-exam.py {{ARGS}}

# ==================== Challenges ====================

# List all challenges
list:
  @echo "Platform Challenges:"
  @find challenges -mindepth 2 -maxdepth 2 -type d -not -name "0-*" | sort | sed 's|challenges/||'

# Run domain with interactive navigation (next/prev/goto)
domain name *ARGS:
  ./scripts/run-domain.sh "{{name}}" {{ARGS}}

# Helper to run challenge via test runner
[private]
_run domain test:
  ./scripts/run-exercise.sh "{{domain}}/{{test}}" --interactive

# ==================== GitOps Domain (25%) ====================

# Run all GitOps challenges
domain-gitops *ARGS:
  @just exam domain-gitops {{ARGS}}

# Fix broken ArgoCD sync
gitops-fix: (_run "1-gitops" "broken-sync")

# Configure Argo Rollouts canary deployment
gitops-canary: (_run "1-gitops" "canary-rollout")

# Setup Tekton trigger pipeline
gitops-tekton: (_run "1-gitops" "tekton-pipeline")

# ArgoCD ApplicationSet environment promotion
gitops-appset: (_run "1-gitops" "env-promotion")

# Blue/Green deployment with Argo Rollouts
gitops-bluegreen: (_run "1-gitops" "bluegreen")

# Istio canary release troubleshooting
gitops-istio: (_run "1-gitops" "istio-canary")

# ==================== Platform APIs Domain (25%) ====================

# Run all Platform APIs challenges
domain-platform *ARGS:
  @just exam domain-apis {{ARGS}}

# Create platform CRD for self-service
platform-crd: (_run "2-apis" "platform-crd")

# Add status subresource to CRD
platform-crd-status: (_run "2-apis" "crd-status")

# Troubleshoot operator RBAC
platform-operator: (_run "2-apis" "operator-rbac")

# Self-service provisioning with Crossplane
platform-selfservice: (_run "2-apis" "crossplane-workflow")

# ==================== Observability Domain (20%) ====================

# Run all Observability challenges
domain-observability *ARGS:
  @just exam domain-observability {{ARGS}}

# Fix broken ServiceMonitor selector
obs-monitor: (_run "3-observability" "broken-servicemonitor")

# Fix OpenCost cost allocation labels
obs-cost: (_run "3-observability" "cost-allocation")

# Fix broken Grafana dashboard
obs-grafana: (_run "3-observability" "grafana-dashboard")

# Fix Prometheus alerting rule
obs-alerting: (_run "3-observability" "prometheus-alert")

# Configure Jaeger tracing for application
obs-tracing: (_run "3-observability" "jaeger-trace")

# Diagnose and fix pod failure incident
obs-incident: (_run "3-observability" "incident-fix")

# ==================== Architecture Domain (15%) ====================

# Run all Architecture challenges
domain-architecture *ARGS:
  @just exam domain-architecture {{ARGS}}

# Inject fault using Istio VirtualService
arch-fault: (_run "4-architecture" "istio-fault-injection")

# Configure NetworkPolicy for multi-tenancy
arch-networkpolicy: (_run "4-architecture" "network-policy")

# Configure ResourceQuota and LimitRange
arch-quota: (_run "4-architecture" "resource-quota")

# Configure a PodDisruptionBudget for availability
arch-pdb: (_run "4-architecture" "pod-disruption-budget")

# Configure StorageClass for persistent storage
arch-storage: (_run "4-architecture" "storage-class")

# Configure Istio VirtualService traffic splitting
arch-mesh: (_run "4-architecture" "service-mesh")

# ==================== Security Domain (15%) ====================

# Run all Security challenges
domain-security *ARGS:
  @just exam domain-security {{ARGS}}

# Fix broken Kyverno policy
security-policy: (_run "5-security" "kyverno-policy")

# Troubleshoot RBAC permissions
security-rbac: (_run "5-security" "rbac-fix")

# Apply least-privilege RBAC for ServiceAccount
security-rbac-min: (_run "5-security" "rbac-minimal")

# Apply Pod Security Standards to namespace
security-pss: (_run "5-security" "pod-security")

# Enable strict mTLS with Istio
security-mtls: (_run "5-security" "istio-mtls")

# Create Gatekeeper constraint
security-gatekeeper: (_run "5-security" "gatekeeper-constraint")

# Fix broken ExternalSecret sync
security-eso: (_run "5-security" "external-secrets")

# Fix a ValidatingAdmissionPolicy (native CEL admission)
security-vap: (_run "5-security" "validating-admission-policy")

# ==================== Scalability Domain ====================

# Run all Scalability challenges
domain-scalability *ARGS:
  @just exam domain-scalability {{ARGS}}

# Configure Horizontal Pod Autoscaling
scal-hpa: (_run "6-scalability" "hpa-cpu")

# ==================== Packaging Domain ====================

# Run all Packaging challenges
domain-packaging *ARGS:
  @just exam domain-packaging {{ARGS}}

# Fix Broken Helm Chart
pkg-helm: (_run "7-packaging" "helm-templating")

# Create Production Kustomize Overlay
pkg-kustomize: (_run "7-packaging" "kustomize-overlays")

# ==================== Developer Experience Domain ====================

# Run all Developer Experience challenges
domain-devex *ARGS:
  @just exam domain-devex {{ARGS}}

# Repair a self-service golden path
devex-golden-path: (_run "8-devex" "golden-path")

# ==================== Measurement Domain ====================

# Run all Measurement challenges
domain-measurement *ARGS:
  @just exam domain-measurement {{ARGS}}

# Make the platform's DORA signals load in Prometheus
measure-dora: (_run "9-measurement" "dora-metrics")
