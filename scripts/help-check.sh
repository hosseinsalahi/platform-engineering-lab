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

ok() { printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
die() { printf "  \033[0;31m✗\033[0m %s\n" "$1"; exit 1; }

run() {
  local label="$1"
  shift
  if "$@" >/dev/null; then
    ok "$label"
  else
    die "$label"
  fi
}

echo "Checking --help for repo CLIs..."

# Scripts
run "scripts/check.sh --help" bash ./scripts/check.sh --help
run "scripts/doctor.sh --help" bash ./scripts/doctor.sh --help
run "scripts/install-cli.sh --help" ./scripts/install-cli.sh --help
run "scripts/upgrade-cli.sh --help" bash ./scripts/upgrade-cli.sh --help
run "scripts/run-domain.sh --help" ./scripts/run-domain.sh --help
run "scripts/run-exercise.sh --help" ./scripts/run-exercise.sh --help
run "scripts/run-exam.sh --help" ./scripts/run-exam.sh --help
run "scripts/parse-assert.sh --help" bash ./scripts/parse-assert.sh --help
run "scripts/auto-fix.sh --help" bash ./scripts/auto-fix.sh --help
run "scripts/preflight.py --help" python3 ./scripts/preflight.py --help
run "scripts/check-md-links.py --help" python3 ./scripts/check-md-links.py --help
run "scripts/exam-tools.py --help" python3 ./scripts/exam-tools.py --help
run "scripts/solve-exam.py --help" python3 ./scripts/solve-exam.py --help

# Challenge entrypoints
run "scripts/provision-cluster.sh --help" bash ./scripts/provision-cluster.sh --help
run "scripts/provision-cluster-light.sh --help" bash ./scripts/provision-cluster-light.sh --help

# Just wrappers (spot-check)
run "just exam-tools --help" just exam-tools --help
run "just solve --help" just solve --help
run "just provision-exam --help" just provision-exam --help
run "just provision-tools --help" just provision-tools --help
run "just domain 1-gitops --help" just domain 1-gitops --help
run "just exam-1 --help" just exam-1 --help

ok "All --help checks passed"
