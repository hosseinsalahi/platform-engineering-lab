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

OS=$(uname -s || echo unknown)

usage() {
  cat <<'EOF'
Usage: install-cli.sh [--apply|--print] [--force]

Options:
  --apply   Execute the install steps (Linux: with sudo; macOS: via Homebrew)
  --print   Print the install steps without running anything
  --force   Reinstall/overwrite even if tools already present (macOS brew; Linux apply mode downloads again)

Notes:
  - Default mode is --apply on macOS (Homebrew, requires brew) and --print on Linux
  - --print never modifies the machine on either OS: no installs, no Podman machine
  - For Linux, architecture defaults to x86_64; adjust URLs for arm64
EOF
}

MODE="print"
MODE_EXPLICIT=0
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply"; MODE_EXPLICIT=1; shift ;;
    --print) MODE="print"; MODE_EXPLICIT=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# macOS has always installed on a bare invocation, and README/justfile document
# `just install-cli` that way, so keep apply as the default there - but honour an
# explicit --print, which previously installed anyway.
if [[ "$OS" == "Darwin" && "$MODE_EXPLICIT" -eq 0 ]]; then
  MODE="apply"
fi

if [[ "$OS" == "Darwin" && "$MODE" == "print" ]]; then
  cat <<'PRINT_EOF'
macOS detected. Printing recommended install commands (nothing has been run):

brew install podman kuttl kind kubernetes-cli helm istioctl tektoncd-cli argocd kyverno yq

# Podman machine (required, especially on Apple Silicon)
podman machine init --cpus 4 --memory 8192 --disk-size 50
podman machine start

# Point kind at Podman
export KIND_EXPERIMENTAL_PROVIDER=podman

# Then verify
just check
PRINT_EOF
  exit 0
fi

if [[ "$OS" == "Darwin" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required on macOS. Install: https://brew.sh" >&2
    exit 1
  fi
  echo "Installing CLIs via Homebrew..."
  FORMULAE=(podman kuttl kind kubernetes-cli helm istioctl tektoncd-cli argocd kyverno yq)
  for f in "${FORMULAE[@]}"; do
    if brew list --formula "$f" >/dev/null 2>&1; then
      if [[ $FORCE -eq 1 ]]; then
        echo "  ↻ Reinstalling $f"
        brew reinstall "$f" || brew install "$f"
      else
        echo "  ✓ $f already installed"
      fi
    else
      brew install "$f"
    fi
  done
  echo ""
  echo "Setting up Podman machine (required for macOS, especially Apple Silicon)..."
  if ! podman machine list --format "{{.Name}}" 2>/dev/null | grep -q .; then
    echo "  → Initializing Podman machine with recommended resources (4 CPUs, 8GB RAM, 50GB disk)..."
    podman machine init --cpus 4 --memory 8192 --disk-size 50
    podman machine start
    echo "  ✓ Podman machine initialized and started"
  else
    if ! podman machine list --format "{{.Running}}" 2>/dev/null | grep -q "true"; then
      echo "  → Starting Podman machine..."
      podman machine start
      echo "  ✓ Podman machine started"
    else
      echo "  ✓ Podman machine already running"
    fi
  fi
  echo ""
  echo "Configuring kind to use Podman..."
  echo "Add to your shell profile: export KIND_EXPERIMENTAL_PROVIDER=podman"
  echo ""
  echo "If KUTTL isn't found as a kubectl plugin, ensure PATH is updated."
  echo "Verify with: just check"
elif [[ "$OS" == "Linux" ]]; then
  # Detect distribution
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  DISTRO=${ID_LIKE:-${ID:-unknown}}
  if [[ "$MODE" == "print" ]]; then
    echo "Linux detected ($DISTRO). Printing recommended install commands:"
    echo "Note: The following commands use pinned versions and verify checksums for security."
    echo ""
  fi
  
  # Checksum verification helper script (embedded in print mode if needed, but here unused)
  # verify_sum logic removed as it was unused.

  case "$DISTRO" in
    *debian*|*ubuntu*|*rhel*|*centos*|*fedora*)
      # Common install logic for Linux distros
      if [[ "$MODE" == "print" ]]; then
        cat <<EOF
# Dependencies
sudo apt-get update && sudo apt-get install -y curl git python3 python3-pip podman || \
sudo dnf install -y curl git python3 python3-pip podman

# Configure kind to use podman
export KIND_EXPERIMENTAL_PROVIDER=podman

# kubectl (v1.36.3) - within the supported +/-1 minor skew of the v1.35 cluster
curl -LO "https://dl.k8s.io/v1.36.3/bin/linux/amd64/kubectl"
echo "ebbd080e7c2e275093b55915722043257eb24004363e20acb3c4d71919f88336  kubectl" | sha256sum --check
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# kind (v0.33.0) - must be new enough for the kindest/node image in kind-config.yaml
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
echo "aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d  kind" | sha256sum --check
chmod +x kind && sudo mv kind /usr/local/bin/

# helm (v4.2.4) - Helm 3 bug fixes ended July 2026; v2-format charts still work unchanged
curl -LO https://get.helm.sh/helm-v4.2.4-linux-amd64.tar.gz
echo "c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3  helm-v4.2.4-linux-amd64.tar.gz" | sha256sum --check
tar -zxvf helm-v4.2.4-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 helm-v4.2.4-linux-amd64.tar.gz

# kuttl (v0.26.0)
curl -L https://github.com/kudobuilder/kuttl/releases/download/v0.26.0/kuttl_0.26.0_linux_x86_64.tar.gz -o kuttl.tar.gz
echo "a1e85cf519f19260b16f8c2c77b475c6b43c10313aee1ad02469f37da08dbe86  kuttl.tar.gz" | sha256sum --check
tar -xzf kuttl.tar.gz kubectl-kuttl && sudo mv kubectl-kuttl /usr/local/bin/ && rm kuttl.tar.gz

# istioctl (1.30.3) - keep the minor in step with ISTIO_CHART_VERSION in chart-versions.env
# WARNING: the upstream installer script is not checksum-verified.
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.30.3 sh -
sudo mv istio-1.30.3/bin/istioctl /usr/local/bin/

# tekton CLI (v0.43.0)
curl -LO https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Linux_x86_64.tar.gz
echo "8a5cbeed07fcfd519199c84f93d08ec2c5d3ccea987b4573b1cd3b8def19ceb5  tkn_0.43.0_Linux_x86_64.tar.gz" | sha256sum --check
tar -xzf tkn_0.43.0_Linux_x86_64.tar.gz tkn && sudo mv tkn /usr/local/bin/ && rm tkn_0.43.0_Linux_x86_64.tar.gz

# argocd (v3.4.6) - the CLI major must match the Argo CD server installed by the chart
curl -sLO https://github.com/argoproj/argo-cd/releases/download/v3.4.6/argocd-linux-amd64
echo "af05f97444a140591a12c136f2be6ffafd95aed03b34a500957ff8aedb998181  argocd-linux-amd64" | sha256sum --check
chmod +x argocd-linux-amd64 && sudo mv argocd-linux-amd64 /usr/local/bin/argocd

# kyverno CLI (v1.19.0)
curl -LO https://github.com/kyverno/kyverno/releases/download/v1.19.0/kyverno-cli_v1.19.0_linux_x86_64.tar.gz
echo "f5b4dc73c8e2f3f66e8e0034dc370e6eb6c4617eff7d5ae3838d2200034eb421  kyverno-cli_v1.19.0_linux_x86_64.tar.gz" | sha256sum --check
tar -xzf kyverno-cli_v1.19.0_linux_x86_64.tar.gz kyverno && sudo mv kyverno /usr/local/bin/ && rm kyverno-cli_v1.19.0_linux_x86_64.tar.gz

# yq (v4.50.1)
curl -Lo yq https://github.com/mikefarah/yq/releases/download/v4.50.1/yq_linux_amd64
echo "c7a1278e6bbc4924f41b56db838086c39d13ee25dcb22089e7fbf16ac901f0d4  yq" | sha256sum --check
chmod +x yq && sudo mv yq /usr/local/bin/

# Verify
just check
EOF
      else
        # APPLY MODE
        echo "Installing tools..."
        
        # Package managers
        if command -v apt-get >/dev/null; then
          sudo apt-get update
          sudo apt-get install -y curl git python3 python3-pip podman
        elif command -v dnf >/dev/null; then
           sudo dnf install -y curl git python3 python3-pip podman
        fi

        export KIND_EXPERIMENTAL_PROVIDER=podman
        
        # Helper to download and verify
        install_bin() {
          local url=$1
          local sha=$2
          local name=$3
          echo "  Downloading $name..."
          curl -fsSL "$url" -o "$name"
          echo "$sha  $name" | sha256sum --check || exit 1
          chmod +x "$name"
          sudo mv "$name" /usr/local/bin/
        }

        # Kubectl
        install_bin "https://dl.k8s.io/v1.36.3/bin/linux/amd64/kubectl" \
                    "ebbd080e7c2e275093b55915722043257eb24004363e20acb3c4d71919f88336" "kubectl"
        
        # Kind
        install_bin "https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64" \
                    "aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d" "kind"

        # Helm
        echo "  Downloading Helm..."
        curl -fsSL https://get.helm.sh/helm-v4.2.4-linux-amd64.tar.gz -o helm.tar.gz
        echo "c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3  helm.tar.gz" | sha256sum --check
        tar -zxf helm.tar.gz
        sudo mv linux-amd64/helm /usr/local/bin/helm
        rm -rf linux-amd64 helm.tar.gz

        # Kuttl
        echo "  Downloading Kuttl..."
        curl -fsSL https://github.com/kudobuilder/kuttl/releases/download/v0.26.0/kuttl_0.26.0_linux_x86_64.tar.gz -o kuttl.tar.gz
        echo "a1e85cf519f19260b16f8c2c77b475c6b43c10313aee1ad02469f37da08dbe86  kuttl.tar.gz" | sha256sum --check
        tar -xzf kuttl.tar.gz kubectl-kuttl
        sudo mv kubectl-kuttl /usr/local/bin/
        rm kuttl.tar.gz

        # Istio (Keep shell pipe for now, but note risk. Pinning version is safer than latest.)
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.30.3 sh -
        sudo mv istio-1.30.3/bin/istioctl /usr/local/bin/
        rm -rf istio-1.30.3

        # Tekton
        echo "  Downloading Tekton..."
        curl -fsSL https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Linux_x86_64.tar.gz -o tkn.tar.gz
        echo "8a5cbeed07fcfd519199c84f93d08ec2c5d3ccea987b4573b1cd3b8def19ceb5  tkn.tar.gz" | sha256sum --check
        tar -xzf tkn.tar.gz tkn
        sudo mv tkn /usr/local/bin/
        rm tkn.tar.gz

        # ArgoCD
        install_bin "https://github.com/argoproj/argo-cd/releases/download/v3.4.6/argocd-linux-amd64" \
                    "af05f97444a140591a12c136f2be6ffafd95aed03b34a500957ff8aedb998181" "argocd"

        # Kyverno
        echo "  Downloading Kyverno..."
        curl -fsSL https://github.com/kyverno/kyverno/releases/download/v1.19.0/kyverno-cli_v1.19.0_linux_x86_64.tar.gz -o kyverno.tar.gz
        echo "f5b4dc73c8e2f3f66e8e0034dc370e6eb6c4617eff7d5ae3838d2200034eb421  kyverno.tar.gz" | sha256sum --check
        tar -xzf kyverno.tar.gz kyverno
        sudo mv kyverno /usr/local/bin/
        rm kyverno.tar.gz

        # Yq
        install_bin "https://github.com/mikefarah/yq/releases/download/v4.50.1/yq_linux_amd64" \
                    "c7a1278e6bbc4924f41b56db838086c39d13ee25dcb22089e7fbf16ac901f0d4" "yq"

        echo ""
        echo "Done. Run: just check"
      fi
      ;;
    *)
      # Fallback for generic Linux
      echo "Automatic installation for this distro is not supported in this script version."
      exit 1
      ;;
  esac
fi
