#!/usr/bin/env bash
# Solve every challenge in sequence and report a pass/fail table.
#
# This is the check that proves the repo actually works: `just preflight` only
# validates YAML shape, and CI's smoke test covers one trivial challenge. Two
# whole classes of breakage - an upstream chart dropping an API version, and a
# challenge whose answer no longer produces the asserted state - are invisible
# until something replays every answer against a real cluster.
#
# Requires a provisioned cluster. Writes a Markdown summary to
# $GITHUB_STEP_SUMMARY when running in GitHub Actions.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SOLVE_ALL_LOG_DIR:-${ROOT_DIR}/.solve-all-logs}"

usage() {
  cat <<'USAGE_EOF'
Usage: solve-all.sh [--only <domain/challenge>]... [--log-dir DIR]

Solves every challenge (or just the ones named with --only) and prints a summary.
Exits non-zero if any challenge fails.
USAGE_EOF
  exit "${1:-0}"
}

ONLY=()
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --only) ONLY+=("$2"); shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

mkdir -p "$LOG_DIR"
cd "$ROOT_DIR"

if [[ ${#ONLY[@]} -gt 0 ]]; then
  CHALLENGES=("${ONLY[@]}")
else
  # read into an array without mapfile - macOS ships bash 3.2
  CHALLENGES=()
  while IFS= read -r _line; do
    [[ -n "$_line" ]] && CHALLENGES+=("$_line")
  done < <(
    find challenges -mindepth 2 -maxdepth 2 -type d \
      | sed 's|challenges/||' \
      | grep -v '^0-' \
      | sort
  )
fi

printf '%s challenges to solve\n\n' "${#CHALLENGES[@]}"

results=()
failed=0
started=$(date +%s)

for challenge in "${CHALLENGES[@]}"; do
  log="${LOG_DIR}/${challenge//\//__}.log"
  start=$(date +%s)
  if python3 scripts/solve-exam.py --challenge "$challenge" >"$log" 2>&1; then
    status=PASS
  else
    status=FAIL
    failed=$((failed + 1))
  fi
  duration=$(( $(date +%s) - start ))
  results+=("${status}|${challenge}|${duration}")
  printf '[%s] %-42s %ss\n' "$status" "$challenge" "$duration"
done

total=$(( $(date +%s) - started ))
passed=$(( ${#CHALLENGES[@]} - failed ))

printf '\n%s/%s passed in %ss\n' "$passed" "${#CHALLENGES[@]}" "$total"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Challenge results"
    echo ""
    echo "**${passed}/${#CHALLENGES[@]} passed** in ${total}s"
    echo ""
    echo "| Result | Challenge | Duration |"
    echo "|---|---|---|"
    for row in "${results[@]}"; do
      IFS='|' read -r status challenge duration <<<"$row"
      icon=$([[ "$status" == PASS ]] && echo ':white_check_mark:' || echo ':x:')
      echo "| ${icon} ${status} | \`${challenge}\` | ${duration}s |"
    done
    if [[ $failed -gt 0 ]]; then
      echo ""
      echo "Logs for failing challenges are in the run artifacts."
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ $failed -gt 0 ]]; then
  echo ""
  echo "Failing challenges:"
  for row in "${results[@]}"; do
    IFS='|' read -r status challenge _ <<<"$row"
    [[ "$status" == FAIL ]] && echo "  - $challenge (see ${LOG_DIR}/${challenge//\//__}.log)"
  done
  exit 1
fi
