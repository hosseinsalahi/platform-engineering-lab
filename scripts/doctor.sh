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

CLUSTER_NAME="${CNPE_CLUSTER_NAME:-battleground}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

ok(){ printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
warn(){ printf "  \033[1;33m-\033[0m %s\n" "$1"; }
bad(){ printf "  \033[0;31m✗\033[0m %s\n" "$1"; }
hint(){ printf "      %s\n" "$1"; }
section(){ printf "\n\033[1m%s\033[0m\n" "$1"; }

usage() {
  cat <<'USAGE_EOF'
Usage: doctor.sh [--exam <exam>] [--skip-tools]

Diagnose this repo's environment: local toolchain, kind cluster, installed platform
components and leftover state. Reports; it does not change anything.

Options:
  --exam <exam>   Only report on components that exam needs (e.g. exam-1,
                  domain-gitops). Uses scripts/exam-tools.py.
  --skip-tools    Skip the local toolchain section (scripts/check.sh).
  -h, --help      Show this help.

Exit status is non-zero when the toolchain check fails, the cluster is
unreachable or unhealthy, or an installed component is not ready. A component
that is simply absent is reported, not failed - `just provision-exam`
deliberately installs a subset - unless --exam says the exam needs it.
USAGE_EOF
  exit "${1:-0}"
}

EXAM=""
SKIP_TOOLS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --exam) EXAM="${2:-}"; [[ -n "$EXAM" ]] || { echo "--exam needs a value" >&2; exit 2; }; shift 2 ;;
    --exam=*) EXAM="${1#*=}"; shift ;;
    --skip-tools) SKIP_TOOLS=true; shift ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

failures=0

# ---------------------------------------------------------------- toolchain
if [[ "$SKIP_TOOLS" == false ]]; then
  section "Local toolchain"
  if bash "${SCRIPT_DIR}/check.sh"; then
    :
  else
    failures=$((failures+1))
  fi
fi

# ------------------------------------------------------------------ cluster
section "Cluster"

cluster_up=false
if ! command -v kubectl >/dev/null 2>&1; then
  bad "kubectl missing - cannot inspect the cluster"
  failures=$((failures+1))
elif ! command -v kind >/dev/null 2>&1; then
  bad "kind missing - cannot inspect the cluster"
  failures=$((failures+1))
else
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    ok "kind cluster '${CLUSTER_NAME}' exists"
  else
    bad "no kind cluster named '${CLUSTER_NAME}'"
    hint "run: just provision   (or set CNPE_CLUSTER_NAME to an existing cluster)"
    failures=$((failures+1))
  fi

  current_context="$(kubectl config current-context 2>/dev/null || echo none)"
  if [[ "$current_context" == "$KIND_CONTEXT" ]]; then
    ok "kubectl context is ${KIND_CONTEXT}"
  else
    bad "kubectl context is '${current_context}', expected '${KIND_CONTEXT}'"
    hint "run: kubectl config use-context ${KIND_CONTEXT}"
    failures=$((failures+1))
  fi

  if kubectl --context "$KIND_CONTEXT" get --raw='/readyz' >/dev/null 2>&1; then
    server_ver="$(kubectl --context "$KIND_CONTEXT" version -o json 2>/dev/null \
      | sed -n 's/.*"gitVersion": *"\(v[0-9][^"]*\)".*/\1/p' | tail -n1)"
    ok "API server reachable${server_ver:+ (${server_ver})}"
    cluster_up=true
  else
    bad "API server for ${KIND_CONTEXT} is not reachable"
    failures=$((failures+1))
  fi

  if [[ "$cluster_up" == true ]]; then
    notready="$(kubectl --context "$KIND_CONTEXT" get nodes --no-headers 2>/dev/null \
      | awk '$2 != "Ready" {print $1}' || true)"
    total="$(kubectl --context "$KIND_CONTEXT" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ -z "$notready" ]]; then
      ok "${total} node(s) Ready"
    else
      bad "node(s) not Ready: $(echo "$notready" | tr '\n' ' ' | sed 's/ *$//')"
      failures=$((failures+1))
    fi
  fi
fi

# --------------------------------------------------------------- components
# tool|helm release|namespace   (empty release = not installed by helm)
COMPONENTS=(
  "argocd|argocd|argocd"
  "argo-rollouts|argo-rollouts|argo-rollouts"
  "tekton||tekton-pipelines"
  "kyverno|kyverno|kyverno"
  "gatekeeper|gatekeeper|gatekeeper-system"
  "prometheus-stack|prometheus-stack|monitoring"
  "jaeger|jaeger|jaeger"
  "crossplane|crossplane|crossplane-system"
  "istio|istiod|istio-system"
  "external-secrets|external-secrets|external-secrets"
  "metrics-server|metrics-server|kube-system"
  "opencost|opencost|opencost"
)

wanted=""
exam_error=""
if [[ -n "$EXAM" ]]; then
  # set -E propagates the ERR trap into the command substitution, so a failing
  # exam-tools.py would print a spurious ERROR line. Handle the failure here instead.
  trap - ERR
  set +e
  wanted="$(python3 "${SCRIPT_DIR}/exam-tools.py" --exam "$EXAM" --format lines 2>&1)"
  exam_rc=$?
  set -e
  trap on_error ERR
  if [[ "$exam_rc" -ne 0 ]]; then
    exam_error="could not resolve exam '${EXAM}': ${wanted}"
    failures=$((failures+1))
    wanted=""
    EXAM=""
  fi
fi

if [[ -n "$EXAM" ]]; then
  section "Components required by ${EXAM}"
else
  section "Components"
fi
[[ -n "$exam_error" ]] && bad "$exam_error"

# Report deployments/statefulsets in a namespace that are not fully ready.
unready_workloads() {
  local ns="$1" selector="$2" out="" line name ready desired
  local -a args=(--context "$KIND_CONTEXT" -n "$ns" --no-headers)
  [[ -n "$selector" ]] && args+=(-l "$selector")
  while read -r line; do
    [[ -z "$line" ]] && continue
    name="$(echo "$line" | awk '{print $1}')"
    ready="$(echo "$line" | awk '{print $2}')"
    desired="$(echo "$line" | awk '{print $3}')"
    [[ "$ready" == "<none>" ]] && ready=0
    [[ "$desired" == "<none>" ]] && desired=0
    if [[ "$ready" != "$desired" ]]; then
      out+="${out:+, }${name} (${ready}/${desired})"
    fi
  done < <(kubectl "${args[@]}" get deploy,statefulset \
      -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas \
      2>/dev/null || true)
  printf '%s' "$out"
}

if [[ "$cluster_up" != true ]]; then
  warn "cluster not reachable - skipping component checks"
else
  for entry in "${COMPONENTS[@]}"; do
    IFS='|' read -r tool release ns <<<"$entry"

    if [[ -n "$EXAM" ]] && ! grep -qx "$tool" <<<"$wanted"; then
      continue
    fi

    installed=false
    if [[ -n "$release" ]]; then
      helm status "$release" -n "$ns" --kube-context "$KIND_CONTEXT" >/dev/null 2>&1 && installed=true
    else
      # tekton is applied from a release manifest, not helm
      kubectl --context "$KIND_CONTEXT" get ns "$ns" >/dev/null 2>&1 && installed=true
    fi

    if [[ "$installed" != true ]]; then
      if [[ -n "$EXAM" ]]; then
        bad "${tool} not installed (needed by ${EXAM})"
        hint "run: just provision-exam ${EXAM}"
        failures=$((failures+1))
      else
        warn "${tool} not installed"
      fi
      continue
    fi

    # kube-system holds cluster components too - scope it to the release
    selector=""
    [[ "$ns" == "kube-system" ]] && selector="app.kubernetes.io/instance=${release}"

    unready="$(unready_workloads "$ns" "$selector")"
    if [[ -z "$unready" ]]; then
      ok "${tool} (${ns})"
    else
      bad "${tool} (${ns}) not ready: ${unready}"
      hint "kubectl --context ${KIND_CONTEXT} -n ${ns} get pods"
      failures=$((failures+1))
    fi
  done
fi

# ------------------------------------------------------------------ leftovers
section "Leftover state"

if [[ "$cluster_up" == true ]]; then
  stray="$(kubectl --context "$KIND_CONTEXT" get ns --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null \
    | grep '^cnpe-' || true)"
  if [[ -z "$stray" ]]; then
    ok "no leftover cnpe-* namespaces"
  else
    stray_list="$(echo "$stray" | tr '\n' ' ' | sed 's/ *$//')"
    warn "leftover challenge namespaces: ${stray_list}"
    hint "kubectl --context ${KIND_CONTEXT} delete ns ${stray_list}"
  fi
else
  warn "cluster not reachable - skipping namespace check"
fi

if [[ -f "${ROOT_DIR}/kubeconfig" ]]; then
  warn "stale ${ROOT_DIR}/kubeconfig (KUTTL writes this; gitignored, but it can shadow your real config)"
  hint "rm ${ROOT_DIR}/kubeconfig"
else
  ok "no stray repo-root kubeconfig"
fi

leftover_dl=()
for f in tekton-release.yaml tekton-triggers-release.yaml tekton-pipeline.yaml tekton-triggers-crds.yaml; do
  [[ -f "${ROOT_DIR}/${f}" ]] && leftover_dl+=("$f")
done
if [[ ${#leftover_dl[@]} -eq 0 ]]; then
  ok "no leftover provisioning downloads"
else
  warn "leftover provisioning downloads: ${leftover_dl[*]}"
  hint "an interrupted provision left these; they are not gitignored - rm them before committing"
fi

# ----------------------------------------------------------------- summary
echo ""
if [[ "$failures" -gt 0 ]]; then
  bad "${failures} problem(s) found"
  exit 1
fi
ok "Diagnostics completed"
