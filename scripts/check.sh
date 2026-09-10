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

ok(){ printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
warn(){ printf "  \033[1;33m-\033[0m %s\n" "$1"; }
die(){ printf "  \033[0;31m✗\033[0m %s\n" "$1"; exit 1; }

# Minimum versions. These are floors, not pins: anything at or above them is fine.
# The floors exist because an old toolchain fails in confusing ways much later -
# a stale kubectl drifts outside the supported +/-1 skew against the cluster's
# API server, and an old kind may not understand the kindest/node image in
# scripts/kind-config.yaml.
MIN_KIND_VERSION="0.30.0"
MIN_KUBECTL_MINOR="34"
MIN_HELM_MAJOR="3"

# version_ge <have> <want> - true when have >= want, compared as dotted versions
version_ge(){ [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

usage() {
  cat <<'USAGE_EOF'
Usage: check.sh

Verify required local tools are installed and usable for the battleground.
USAGE_EOF
  exit "${1:-0}"
}

case "${1:-}" in
  -h|--help) usage 0 ;;
esac

# Check Podman
command -v podman >/dev/null 2>&1 || die "podman missing (required for kind cluster)"
ok "podman $(podman --version 2>/dev/null | cut -d' ' -f3 || echo present)"

# Check Podman machine on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
  if ! podman machine list --format "{{.Running}}" 2>/dev/null | grep -q "true"; then
    die "podman machine not running (run: podman machine init && podman machine start)"
  fi
  ok "podman machine running"
fi

# Check KIND_EXPERIMENTAL_PROVIDER is set
if [[ -z "${KIND_EXPERIMENTAL_PROVIDER:-}" ]]; then
  warn "KIND_EXPERIMENTAL_PROVIDER not set (add: export KIND_EXPERIMENTAL_PROVIDER=podman)"
else
  ok "KIND_EXPERIMENTAL_PROVIDER=${KIND_EXPERIMENTAL_PROVIDER}"
fi

command -v kubectl >/dev/null 2>&1 || die "kubectl missing"
kubectl_ver="$(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"v\([0-9.]*\)".*/\1/p' | head -n1)"
if [[ -n "$kubectl_ver" ]]; then
  kubectl_minor="$(printf '%s' "$kubectl_ver" | cut -d. -f2)"
  if [[ "$kubectl_minor" -lt "$MIN_KUBECTL_MINOR" ]]; then
    die "kubectl v${kubectl_ver} is too old (need 1.${MIN_KUBECTL_MINOR}+ for the v1.35 cluster; kubectl supports +/-1 minor)"
  fi
  ok "kubectl v${kubectl_ver}"
else
  warn "kubectl present (version not parsed)"
fi

command -v kind >/dev/null 2>&1 || die "kind missing"
kind_ver="$(kind version 2>/dev/null | sed -n 's/^kind v\([0-9.]*\).*/\1/p' | head -n1)"
if [[ -n "$kind_ver" ]]; then
  version_ge "$kind_ver" "$MIN_KIND_VERSION" \
    || die "kind v${kind_ver} is too old (need v${MIN_KIND_VERSION}+ for the node image in scripts/kind-config.yaml)"
  ok "kind v${kind_ver}"
else
  warn "kind present (version not parsed)"
fi

command -v helm >/dev/null 2>&1 || die "helm missing"
helm_ver="$(helm version --short 2>/dev/null | sed -n 's/^v\([0-9.]*\).*/\1/p' | head -n1)"
if [[ -n "$helm_ver" ]]; then
  helm_major="$(printf '%s' "$helm_ver" | cut -d. -f1)"
  if [[ "$helm_major" -lt "$MIN_HELM_MAJOR" ]]; then
    die "helm v${helm_ver} is too old (need v${MIN_HELM_MAJOR}+)"
  fi
  ok "helm v${helm_ver}"
else
  warn "helm present (version not parsed)"
fi

# KUTTL kubectl plugin
kubectl kuttl version >/dev/null 2>&1 || die "KUTTL plugin missing (install from https://kuttl.dev/docs/cli.html)"
ok "kubectl kuttl available"

# Python + PyYAML for assert parsing helper
command -v python3 >/dev/null 2>&1 || die "python3 missing"
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  printf "  \033[0;31m✗\033[0m %s\n" "PyYAML missing - Homebrew and Debian pythons refuse pip installs (PEP 668)"
  printf "      %s\n" "Install it in a virtualenv. With uv:"
  printf "      %s\n" "uv venv && uv pip install pyyaml && source .venv/bin/activate"
  printf "      %s\n" "Without uv:"
  printf "      %s\n" "python3 -m venv .venv && .venv/bin/pip install pyyaml && source .venv/bin/activate"
  exit 1
fi
ok "python3 + PyYAML available"

# Optional tooling
missing=0
if command -v yq >/dev/null 2>&1; then ok "yq present"; else warn "yq not found (optional, recommended)"; missing=$((missing+1)); fi
if command -v argocd >/dev/null 2>&1; then ok "argocd present"; else warn "argocd not found (optional)"; missing=$((missing+1)); fi
if command -v kyverno >/dev/null 2>&1; then ok "kyverno present"; else warn "kyverno not found (optional)"; missing=$((missing+1)); fi
if command -v istioctl >/dev/null 2>&1; then ok "istioctl present"; else warn "istioctl not found (optional)"; missing=$((missing+1)); fi
if command -v tkn >/dev/null 2>&1; then ok "tkn present"; else warn "tkn not found (optional)"; missing=$((missing+1)); fi

echo ""
if [ "$missing" -gt 0 ]; then
  warn "Some optional CLIs are missing. You can:"
  warn "  - Run: devbox shell   # adds argocd, tkn, kyverno, istioctl"
  warn "  - Or install locally: just install-cli (macOS Homebrew)"
fi
ok "Environment checks completed"
