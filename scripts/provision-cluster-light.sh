#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck disable=SC2317,SC2329
on_error() {
  local exit_code=$?
  trap - ERR
  local where=""
  where="$(caller 0 2>/dev/null || true)"
  echo "ERROR: ${0##*/}: ${where:-unknown}: ${BASH_COMMAND} (exit ${exit_code})" >&2
  exit "$exit_code"
}
trap on_error ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/chart-versions.env
source "${SCRIPT_DIR}/chart-versions.env"
CLUSTER_NAME="${CNPE_CLUSTER_NAME:-battleground}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

TOOLS_CSV=""
EXAM_PATH=""

usage() {
  cat <<'EOF'
Usage: provision-cluster-light.sh (--tools csv | --exam exam)

Creates a kind cluster (if needed) and installs only the selected platform tools.

Options:
  --tools csv    Comma-separated tools (e.g. "argocd,argo-rollouts,prometheus-stack")
  --exam exam    Exam identifier to infer tools from (e.g. "exam-1")

Examples:
  ./scripts/provision-cluster-light.sh --tools argocd,argo-rollouts
  ./scripts/provision-cluster-light.sh --exam exam-1
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --tools)
      [[ -n "${2:-}" ]] || { echo "ERROR: --tools requires a value" >&2; usage >&2; exit 2; }
      TOOLS_CSV="${2:-}"
      shift 2
      ;;
    --exam)
      [[ -n "${2:-}" ]] || { echo "ERROR: --exam requires a value" >&2; usage >&2; exit 2; }
      EXAM_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$EXAM_PATH" ]]; then
  # Try resolving the exam path with common patterns
  RESOLVED_EXAM=""
  SEARCH_PATHS=(
    "$EXAM_PATH"
    "${ROOT_DIR}/${EXAM_PATH}"
    "${ROOT_DIR}/exams/${EXAM_PATH}"
    "${ROOT_DIR}/exams/${EXAM_PATH}.yaml"
    "${ROOT_DIR}/exams/exam-${EXAM_PATH}.yaml"
    "${ROOT_DIR}/exams/domain-${EXAM_PATH}.yaml"
  )

  for p in "${SEARCH_PATHS[@]}"; do
    if [[ -f "$p" ]]; then
      RESOLVED_EXAM="$p"
      break
    fi
  done

  if [[ -z "$RESOLVED_EXAM" ]]; then
    echo "ERROR: exam file not found: ${EXAM_PATH}" >&2
    exit 2
  fi
  EXAM_PATH="$RESOLVED_EXAM"
  TOOLS_CSV="$(python3 "${ROOT_DIR}/scripts/exam-tools.py" --exam "${EXAM_PATH}" --format csv)"
fi

if [[ -z "$TOOLS_CSV" ]]; then
  echo "ERROR: must provide --tools or --exam" >&2
  usage >&2
  exit 2
fi

want_tool() {
  local t="$1"
  [[ ",${TOOLS_CSV}," == *",${t},"* ]]
}

# Dependencies
if want_tool opencost && ! want_tool prometheus-stack; then
  TOOLS_CSV="${TOOLS_CSV},prometheus-stack"
fi

echo "=== Battleground Lab Cluster Provisioning (Light) ==="
echo "Tools: ${TOOLS_CSV}"
echo ""

# Ensure cluster exists using the canonical provisioning script.
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  "${ROOT_DIR}/scripts/provision-cluster.sh" --minimal
fi

kind export kubeconfig --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
kubectl config use-context "${KIND_CONTEXT}" >/dev/null 2>&1 || true

echo ""
echo "[1/2] Adding helm repos..."

repos_name=()
repos_url=()
add_repo_needed() { repos_name+=("$1"); repos_url+=("$2"); }

want_tool argocd && add_repo_needed argo https://argoproj.github.io/argo-helm
want_tool argo-rollouts && add_repo_needed argo https://argoproj.github.io/argo-helm
want_tool kyverno && add_repo_needed kyverno https://kyverno.github.io/kyverno/
want_tool gatekeeper && add_repo_needed gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
want_tool prometheus-stack && add_repo_needed prometheus-community https://prometheus-community.github.io/helm-charts
want_tool jaeger && add_repo_needed jaegertracing https://jaegertracing.github.io/helm-charts
want_tool crossplane && add_repo_needed crossplane-stable https://charts.crossplane.io/stable
want_tool istio && add_repo_needed istio https://istio-release.storage.googleapis.com/charts
want_tool external-secrets && add_repo_needed external-secrets https://charts.external-secrets.io
want_tool metrics-server && add_repo_needed metrics-server https://kubernetes-sigs.github.io/metrics-server/
want_tool opencost && add_repo_needed opencost https://opencost.github.io/opencost-helm-chart

uniq_repos_name=()
uniq_repos_url=()
for i in "${!repos_name[@]}"; do
  found=false
  for j in "${!uniq_repos_name[@]}"; do
    if [[ "${uniq_repos_name[$j]}" == "${repos_name[$i]}" ]]; then
      found=true
      break
    fi
  done
  if [[ "$found" != "true" ]]; then
    uniq_repos_name+=("${repos_name[$i]}")
    uniq_repos_url+=("${repos_url[$i]}")
  fi
done

for i in "${!uniq_repos_name[@]}"; do
  helm repo add "${uniq_repos_name[$i]}" "${uniq_repos_url[$i]}" --force-update >/dev/null 2>&1
done
helm repo update >/dev/null 2>&1
echo "      ✓ repos ready"

echo ""
echo "[2/2] Installing selected components..."

install_helm() {
  local name="$1" chart="$2" ns="$3" timeout="$4"
  shift 4
  if helm status "$name" -n "$ns" >/dev/null 2>&1; then
    echo "      ✓ ${name} already installed"
    return 0
  fi
  echo "      Installing ${name}..."
  helm install "$name" "$chart" -n "$ns" --create-namespace --timeout "$timeout" "$@" >/dev/null 2>&1
}

install_tekton_triggers_crds_only() {
  local version="v0.29.1"
  local release_url="https://storage.googleapis.com/tekton-releases/triggers/previous/${version}/release.yaml"

  echo "      Installing tekton triggers CRDs (controllers skipped)..."
  if kubectl get crd triggerbindings.triggers.tekton.dev >/dev/null 2>&1; then
    echo "      ✓ tekton triggers CRDs already present"
  else
    curl -fsSL "$release_url" -o tekton-triggers-release.yaml

    python3 - "$PWD/tekton-triggers-release.yaml" "$PWD/tekton-triggers-crds.yaml" <<'PY'
import sys
from pathlib import Path

try:
  import yaml
except Exception as e:
  raise SystemExit(f"ERROR: PyYAML is required to install Tekton Triggers CRDs ({e}). Run: just check")

in_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

docs = list(yaml.safe_load_all(in_path.read_text("utf-8")))
crds = [d for d in docs if isinstance(d, dict) and d.get("kind") == "CustomResourceDefinition"]
out_path.write_text(yaml.safe_dump_all(crds, sort_keys=False), encoding="utf-8")
PY

    kubectl apply -f tekton-triggers-crds.yaml >/dev/null 2>&1
    rm -f tekton-triggers-release.yaml tekton-triggers-crds.yaml
  fi

  # Remove triggers webhooks/controllers if they exist; otherwise they can block CR operations.
  kubectl delete validatingwebhookconfiguration validation.webhook.triggers.tekton.dev --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete validatingwebhookconfiguration config.webhook.triggers.tekton.dev --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete mutatingwebhookconfiguration webhook.triggers.tekton.dev --ignore-not-found >/dev/null 2>&1 || true

  kubectl delete deployment -n tekton-pipelines tekton-triggers-controller --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete deployment -n tekton-pipelines tekton-triggers-webhook --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete deployment -n tekton-pipelines tekton-triggers-core-interceptors --ignore-not-found >/dev/null 2>&1 || true
}

want_tool argocd && install_helm argocd argo/argo-cd argocd 5m --version "$ARGOCD_CHART_VERSION"
want_tool argo-rollouts && install_helm argo-rollouts argo/argo-rollouts argo-rollouts 3m --version "$ARGO_ROLLOUTS_CHART_VERSION"
want_tool kyverno && install_helm kyverno kyverno/kyverno kyverno 5m --version "$KYVERNO_CHART_VERSION"
want_tool gatekeeper && install_helm gatekeeper gatekeeper/gatekeeper gatekeeper-system 3m --version "$GATEKEEPER_CHART_VERSION"
want_tool jaeger && install_helm jaeger jaegertracing/jaeger jaeger 3m --version "$JAEGER_CHART_VERSION"
want_tool crossplane && install_helm crossplane crossplane-stable/crossplane crossplane-system 3m --version "$CROSSPLANE_CHART_VERSION"
want_tool external-secrets && install_helm external-secrets external-secrets/external-secrets external-secrets 3m --version "$EXTERNAL_SECRETS_CHART_VERSION" --set installCRDs=true
want_tool metrics-server && install_helm metrics-server metrics-server/metrics-server kube-system 3m --version "$METRICS_SERVER_CHART_VERSION" \
  --set "args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname}"

if want_tool tekton; then
  echo "      Installing tekton (pipelines + triggers CRDs)..."
  # Pipelines
  curl -fsSL https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.65.2/release.yaml -o tekton-pipeline.yaml
  kubectl apply -f tekton-pipeline.yaml >/dev/null 2>&1
  rm -f tekton-pipeline.yaml

  install_tekton_triggers_crds_only

  echo "      Waiting for tekton deployments..."
  kubectl wait --for=condition=Available=True --timeout=240s deployment --all -n tekton-pipelines >/dev/null 2>&1
fi

if want_tool prometheus-stack; then
  echo "      Installing monitoring stack (this may take a few minutes)..."
  if ! helm status prometheus-stack -n monitoring >/dev/null 2>&1; then
    if ! helm install prometheus-stack prometheus-community/kube-prometheus-stack \
      --version "$PROMETHEUS_STACK_CHART_VERSION" \
      -n monitoring --create-namespace --timeout 8m --wait \
      --set prometheusOperator.admissionWebhooks.enabled=false \
      --set prometheusOperator.admissionWebhooks.patch.enabled=false \
      --set prometheusOperator.tls.enabled=false >/dev/null 2>&1; then
      echo "      ⚠ Prometheus stack install failed, retrying..."
      helm uninstall prometheus-stack -n monitoring --ignore-not-found >/dev/null 2>&1
      helm install prometheus-stack prometheus-community/kube-prometheus-stack \
      --version "$PROMETHEUS_STACK_CHART_VERSION" \
        -n monitoring --create-namespace --timeout 8m --wait \
        --set prometheusOperator.admissionWebhooks.enabled=false \
        --set prometheusOperator.admissionWebhooks.patch.enabled=false \
        --set prometheusOperator.tls.enabled=false >/dev/null 2>&1
    fi
  else
    echo "      ✓ prometheus-stack already installed"
  fi
fi

if want_tool istio; then
  echo "      Installing istio..."
  install_helm istio-base istio/base istio-system 3m --version "$ISTIO_CHART_VERSION"
  install_helm istiod istio/istiod istio-system 5m --version "$ISTIO_CHART_VERSION"
fi

if want_tool opencost; then
  echo "      Installing opencost..."
  if ! helm status opencost -n opencost >/dev/null 2>&1; then
    helm install opencost opencost/opencost --version "$OPENCOST_CHART_VERSION" -n opencost --create-namespace \
      --set opencost.prometheus.internal.enabled=true \
      --set opencost.prometheus.internal.serviceName=prometheus-stack-kube-prom-prometheus \
      --set opencost.prometheus.internal.namespaceName=monitoring \
      --set opencost.prometheus.internal.port=9090 \
      --timeout 3m >/dev/null 2>&1
  else
    echo "      ✓ opencost already installed"
  fi
fi

echo ""
echo "=== Cluster ready (light)! ==="
