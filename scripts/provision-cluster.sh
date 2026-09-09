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

CLUSTER_NAME="${CNPE_CLUSTER_NAME:-battleground}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/chart-versions.env
source "${SCRIPT_DIR}/chart-versions.env"
MINIMAL=false

usage() {
  cat <<'USAGE_EOF'
Usage: provision-cluster.sh [--minimal]

Creates the kind cluster used by this repo. With --minimal, only the cluster is created.
USAGE_EOF
  exit "${1:-0}"
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    -h|--help) usage 0 ;;
    --minimal) MINIMAL=true; shift ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

# Check if cluster exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster ${CLUSTER_NAME} already exists"
  kubectl config use-context "kind-${CLUSTER_NAME}"
  exit 0
fi

echo "=== Battleground Lab Cluster Provisioning ==="
if [[ "$MINIMAL" == "true" ]]; then
  echo "Mode: Minimal (Cluster only, no platform tools)"
  echo "Estimated time: ~2 minutes"
else
  echo "Estimated time: ~10-15 minutes"
fi
echo ""

# ============ PHASE 1 ============
echo "[1/4] Creating kind cluster..."
echo "      3 nodes (1 control-plane, 2 workers)"
echo "      Ports: 8080→80, 8443→443, 30000-30001"
kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"
echo "      ✓ Cluster created"

if [[ "$MINIMAL" == "true" ]]; then
  echo ""
  echo "=== Minimal Provisioning Complete! ==="
  echo "Skipping platform tools installation (ArgoCD, Istio, etc.)"
  echo ""
  echo "Ready for basic Kubernetes tests."
  exit 0
fi

# ============ PHASE 2 ============
echo ""
echo -n "[2/4] Adding helm repos... 0/9"

# Sequential - counter works
count=0
add_repo() {
  helm repo add "$1" "$2" --force-update >/dev/null 2>&1
  count=$((count + 1))
  echo -ne "\r[2/4] Adding helm repos... ${count}/9"
}
add_repo argo https://argoproj.github.io/argo-helm
add_repo kyverno https://kyverno.github.io/kyverno/
add_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_repo jaegertracing https://jaegertracing.github.io/helm-charts
add_repo opencost https://opencost.github.io/opencost-helm-chart
add_repo istio https://istio-release.storage.googleapis.com/charts
add_repo crossplane-stable https://charts.crossplane.io/stable
add_repo external-secrets https://charts.external-secrets.io
add_repo gatekeeper https://open-policy-agent.github.io/gatekeeper/charts

helm repo update >/dev/null 2>&1
echo -e "\r[2/4] Adding helm repos... ✓ done    "

# ============ PHASE 3 ============
echo ""
echo "[3/4] Installing components..."

# Check if component is installed
is_installed() {
  local name="$1" ns="$2" check="$3"
  if [[ "$check" == "helm" ]]; then
    helm status "$name" -n "$ns" >/dev/null 2>&1
  else
    kubectl get ns "$ns" >/dev/null 2>&1
  fi
}

install_tekton_triggers_crds_only() {
  local version="v0.37.0"
  local release_url="https://infra.tekton.dev/tekton-releases/triggers/previous/${version}/release.yaml"

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

# Count and show installed components
show_progress() {
  local target="$1"
  local count=0
  local status=""

  # Check each component - show all with ✓ for installed
  if is_installed argocd argocd helm; then count=$((count+1)); status+="✓argo,"; else status+="argo,"; fi
  if is_installed argo-rollouts argo-rollouts helm; then count=$((count+1)); status+="✓rollouts,"; else status+="rollouts,"; fi
  if is_installed kyverno kyverno helm; then count=$((count+1)); status+="✓kyverno,"; else status+="kyverno,"; fi
  if is_installed gatekeeper gatekeeper-system helm; then count=$((count+1)); status+="✓gatekeeper,"; else status+="gatekeeper,"; fi
  if is_installed prometheus-stack monitoring helm; then count=$((count+1)); status+="✓prom,"; else status+="prom,"; fi
  if is_installed jaeger jaeger helm; then count=$((count+1)); status+="✓jaeger,"; else status+="jaeger,"; fi
  if is_installed crossplane crossplane-system helm; then count=$((count+1)); status+="✓crossplane,"; else status+="crossplane,"; fi
  if is_installed istio-base istio-system helm; then count=$((count+1)); status+="✓istio,"; else status+="istio,"; fi
  if is_installed tekton tekton-pipelines ns; then count=$((count+1)); status+="✓tekton,"; else status+="tekton,"; fi
  if is_installed istiod istio-system helm; then count=$((count+1)); status+="✓istiod,"; else status+="istiod,"; fi
  if is_installed opencost opencost helm; then count=$((count+1)); status+="✓opencost,"; else status+="opencost,"; fi
  if is_installed external-secrets external-secrets helm; then count=$((count+1)); status+="✓eso"; else status+="eso"; fi

  printf "\r      %d/12 (%s)          " "$count" "$status"

  [[ $count -ge $target ]]
}

# Batch 1: Independent installs (with timeouts to prevent hangs)
helm install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" -n argocd --create-namespace --timeout 5m >/dev/null 2>&1 &
helm install argo-rollouts argo/argo-rollouts --version "$ARGO_ROLLOUTS_CHART_VERSION" -n argo-rollouts --create-namespace --timeout 3m >/dev/null 2>&1 &
helm install kyverno kyverno/kyverno --version "$KYVERNO_CHART_VERSION" -n kyverno --create-namespace --timeout 5m >/dev/null 2>&1 &
helm install gatekeeper gatekeeper/gatekeeper --version "$GATEKEEPER_CHART_VERSION" -n gatekeeper-system --create-namespace --timeout 3m >/dev/null 2>&1 &
helm install jaeger jaegertracing/jaeger --version "$JAEGER_CHART_VERSION" -n jaeger --create-namespace --timeout 3m >/dev/null 2>&1 &
helm install crossplane crossplane-stable/crossplane --version "$CROSSPLANE_CHART_VERSION" -n crossplane-system --create-namespace --timeout 3m >/dev/null 2>&1 &
helm install istio-base istio/base --version "$ISTIO_CHART_VERSION" -n istio-system --create-namespace --timeout 3m >/dev/null 2>&1 &
helm install external-secrets external-secrets/external-secrets --version "$EXTERNAL_SECRETS_CHART_VERSION" -n external-secrets --create-namespace --set installCRDs=true --timeout 3m >/dev/null 2>&1 &
curl -fsSL https://infra.tekton.dev/tekton-releases/pipeline/previous/v0.65.2/release.yaml -o tekton-release.yaml
kubectl apply -f tekton-release.yaml >/dev/null 2>&1 &
install_tekton_triggers_crds_only

until show_progress 9; do sleep 2; done
wait
rm -f tekton-release.yaml

# Batch 1b: Prometheus stack (heavy - run separately with longer timeout)
echo ""
echo "      Installing monitoring stack (this may take a few minutes)..."
if ! helm install prometheus-stack prometheus-community/kube-prometheus-stack \
    --version "$PROMETHEUS_STACK_CHART_VERSION" \
  -n monitoring --create-namespace --timeout 8m --wait \
  --set prometheusOperator.admissionWebhooks.enabled=false \
  --set prometheusOperator.admissionWebhooks.patch.enabled=false \
  --set prometheusOperator.tls.enabled=false \
  2>&1 | grep -v "^$"; then
  echo "      ⚠ Prometheus stack install failed, retrying..."
  helm uninstall prometheus-stack -n monitoring --ignore-not-found >/dev/null 2>&1
  helm install prometheus-stack prometheus-community/kube-prometheus-stack \
    --version "$PROMETHEUS_STACK_CHART_VERSION" \
    -n monitoring --create-namespace --timeout 8m --wait \
    --set prometheusOperator.admissionWebhooks.enabled=false \
    --set prometheusOperator.admissionWebhooks.patch.enabled=false \
    --set prometheusOperator.tls.enabled=false
fi
echo "      ✓ monitoring stack installed"

until show_progress 10; do sleep 2; done

# Batch 2: Depends on istio-base
helm install istiod istio/istiod --version "$ISTIO_CHART_VERSION" -n istio-system --timeout 5m >/dev/null 2>&1 &

until show_progress 11; do sleep 2; done
wait

# Batch 3: Depends on prometheus
helm install opencost opencost/opencost --version "$OPENCOST_CHART_VERSION" -n opencost --create-namespace \
  --set opencost.prometheus.internal.enabled=true \
  --set opencost.prometheus.internal.serviceName=prometheus-stack-kube-prom-prometheus \
  --set opencost.prometheus.internal.namespaceName=monitoring \
  --set opencost.prometheus.internal.port=9090 \
  --timeout 3m >/dev/null 2>&1 &

until show_progress 12; do sleep 2; done
wait
echo ""

# ============ PHASE 4 ============
echo ""
echo "[4/4] Waiting for readiness..."

printf "\r      waiting for argocd..."
kubectl wait --for=condition=Available=True --timeout=300s deployment --all -n argocd >/dev/null 2>&1
echo -e "\r      ✓ argocd ready        "

printf "\r      waiting for kyverno..."
kubectl wait --for=condition=Available=True --timeout=300s deployment --all -n kyverno >/dev/null 2>&1
echo -e "\r      ✓ kyverno ready       "

printf "\r      waiting for gatekeeper..."
kubectl wait --for=condition=Available=True --timeout=300s deployment --all -n gatekeeper-system >/dev/null 2>&1
echo -e "\r      ✓ gatekeeper ready    "

printf "\r      waiting for tekton..."
kubectl wait --for=condition=Available=True --timeout=180s deployment --all -n tekton-pipelines >/dev/null 2>&1
echo -e "\r      ✓ tekton ready        "

echo ""
echo "=== Cluster ready! ==="
echo ""
echo "Run: just list"
