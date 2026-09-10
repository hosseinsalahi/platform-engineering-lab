#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck disable=SC2317,SC2329
on_error() {
    local exit_code=$?
    trap - ERR
    local where=""
    where="$(caller 0 2>/dev/null || true)"
    echo "ERROR: ${0##*/}: ${where:-unknown}: ${BASH_COMMAND} (exit ${exit_code})" >&2
    EXIT_CODE="$exit_code"
    exit "$exit_code"
}
trap on_error ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHALLENGES_DIR="${SCRIPT_DIR}/../challenges"
EXIT_CODE=0
INTERRUPTED=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Cluster configuration
CLUSTER_NAME="${CNPE_CLUSTER_NAME:-battleground}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

# Domain description (portable across bash versions)
get_domain_desc() {
    case "$1" in
        "1-gitops") echo "GitOps and Continuous Delivery (25%)" ;;
        "2-apis") echo "Platform APIs and Self-Service (25%)" ;;
        "3-observability") echo "Observability and Operations (20%)" ;;
        "4-architecture") echo "Platform Architecture (15%)" ;;
        "5-security") echo "Security and Policy Enforcement (15%)" ;;
        "6-scalability") echo "Scalability and Performance" ;;
        "7-packaging") echo "Package Management (Helm/Kustomize)" ;;
        "0-test") echo "Test Setup (validation only)" ;;
        *) echo "Unknown" ;;
    esac
}

usage() {
    cat <<'USAGE_EOF'
Usage: run-exercise.sh <challenge-path> [options]

Examples:
  run-exercise.sh 1-gitops/broken-sync
  run-exercise.sh 1-gitops/canary-rollout --timeout 300

Options:
  --setup-only       Create broken state only (practice mode, no cleanup)
  --check-only       Run assertions only (verify your fix)
  --timeout N        Override timeout in seconds (default: 420)
  --no-cleanup       Skip cleanup after exercise (for debugging)
  --verbose          Show full KUTTL output (for debugging)
  --interactive      Force interactive mode (live timer, wait for Enter)
  --non-interactive  Force non-interactive mode (CI/automation)

Workflow:
  1. Setup creates broken state
  2. You fix the problem using kubectl/CLI
  3. KUTTL validates your fix
  4. Cleanup removes all exercise resources
USAGE_EOF
    exit "${1:-1}"
}

if [[ $# -lt 1 ]]; then
    usage 1
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage 0
fi

EXERCISE_PATH="$1"
SETUP_ONLY=false
CHECK_ONLY=false
NO_CLEANUP=false
VERBOSE=false
TIMEOUT=""
FORCE_INTERACTIVE=""

shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --setup-only) SETUP_ONLY=true; shift ;;
        --check-only) CHECK_ONLY=true; shift ;;
        --no-cleanup) NO_CLEANUP=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --timeout)
            [[ -n "${2:-}" ]] || { echo "ERROR: --timeout requires a value" >&2; usage 1; }
            [[ "${2}" =~ ^[0-9]+$ ]] || { echo "ERROR: --timeout must be an integer (seconds)" >&2; usage 1; }
            TIMEOUT="$2"; shift 2
            ;;
        --interactive) FORCE_INTERACTIVE=true; shift ;;
        --non-interactive) FORCE_INTERACTIVE=false; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

# Verify we're using the expected kind context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "$CURRENT_CONTEXT" != "${KIND_CONTEXT}" ]]; then
    echo -e "${RED}Error: Wrong context '${CURRENT_CONTEXT}', expected '${KIND_CONTEXT}'${NC}"
    echo -e "Run: ${CYAN}just provision${NC} to create the cluster."
    exit 1
fi

# Check for KUTTL
if ! kubectl kuttl version >/dev/null 2>&1 && ! command -v kuttl >/dev/null 2>&1; then
    echo -e "${RED}Error: KUTTL not found!${NC}"
    echo "Please install KUTTL (kubectl plugin or CLI)."
    echo "See: https://kuttl.dev/docs/cli.html"
    echo "Or run: just install-cli"
    exit 1
fi

# Parse domain and challenge
DOMAIN="${EXERCISE_PATH%%/*}"
EXERCISE="${EXERCISE_PATH#*/}"
DOMAIN_DIR="${CHALLENGES_DIR}/${DOMAIN}"
EXERCISE_DIR="${DOMAIN_DIR}/${EXERCISE}"

if [[ ! -d "$EXERCISE_DIR" ]]; then
    echo -e "${RED}Challenge not found: ${EXERCISE_DIR}${NC}"
    echo ""
    echo "Available challenges:"
    find "$CHALLENGES_DIR" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | \
        sed "s|${CHALLENGES_DIR}/||" | sort
    exit 1
fi

# Extract namespace from setup file for cleanup
EXERCISE_NS=""
SETUP_FILE="${EXERCISE_DIR}/setup.yaml"
if [[ -f "$SETUP_FILE" ]]; then
    EXERCISE_NS=$(yq -r 'select(.kind == "Namespace") | .metadata.name' "$SETUP_FILE" 2>/dev/null || true)
    if [[ -z "$EXERCISE_NS" ]]; then
        EXERCISE_NS=$(grep -E "namespace: cnpe-" "$SETUP_FILE" 2>/dev/null | head -1 | awk '{print $2}' || true)
    fi
fi

# Cleanup function (idempotent, tolerate partial failures)
CLEANED="false"
# shellcheck disable=SC2317,SC2329
cleanup_exercise() {
    if [[ "$NO_CLEANUP" == "true" ]]; then
        echo -e "${YELLOW}Skipping cleanup (--no-cleanup)${NC}"
        return
    fi

    # Prevent running twice
    if [[ "$CLEANED" == "true" ]]; then
        return
    fi
    CLEANED="true"

    # Delete resources defined in setup (excluding Namespace) first
    if [[ -f "$SETUP_FILE" ]]; then
        # Best-effort: ignore not found and validation issues
        kubectl delete -f "$SETUP_FILE" --ignore-not-found=true >/dev/null 2>&1 || true
    fi

    # Then delete the exercise namespace (if any)
    if [[ -n "$EXERCISE_NS" ]]; then
        if [[ "$INTERRUPTED" != "true" ]]; then
            echo -e "${YELLOW}Cleaning up namespace: ${EXERCISE_NS}...${NC}"
        fi
        kubectl delete namespace "$EXERCISE_NS" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    fi
}

# Master cleanup
# shellcheck disable=SC2317,SC2329
cleanup_all() {
    set +e
    local exit_code
    exit_code=${EXIT_CODE:-$?}

    if [[ -n "${TIMER_PID:-}" ]]; then
        kill "$TIMER_PID" 2>/dev/null || true
    fi

    printf "\r%80s\r" " "

    rm -f "${KUTTL_STATUS:-}" 2>/dev/null || true

    if [[ "${CLEANUP_ON_EXIT:-false}" == "true" ]]; then
        if [[ "$INTERRUPTED" != "true" ]]; then
            echo ""
        fi
        cleanup_exercise
    fi

    exit "$exit_code"
}

# shellcheck disable=SC2317,SC2329
on_interrupt() {
    EXIT_CODE=130
    INTERRUPTED=true
    echo -e "\n${YELLOW}Interrupted. Cleaning up...${NC}" >&2
    exit 130
}

# Get timeout
if [[ -z "$TIMEOUT" ]]; then
    TIMEOUT=$(grep -E "^timeout:" "${DOMAIN_DIR}/kuttl-test.yaml" 2>/dev/null | awk '{print $2}')
    TIMEOUT=${TIMEOUT:-420}
fi

# Display header
clear
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
printf "${BLUE}║${NC} ${BOLD}%-61s${NC} ${BLUE}║${NC}\n" "Platform Challenge: ${EXERCISE_PATH}"
printf "${BLUE}║${NC} ${CYAN}%-61s${NC} ${BLUE}║${NC}\n" "Category: $(get_domain_desc "$DOMAIN")"
printf "${BLUE}║${NC} ${CYAN}%-61s${NC} ${BLUE}║${NC}\n" "Time Limit: $((TIMEOUT / 60)) minutes"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ -f "${EXERCISE_DIR}/README.md" ]]; then
    cat "${EXERCISE_DIR}/README.md"
    echo ""
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Setup-only mode
if [[ "$SETUP_ONLY" == "true" ]]; then
    echo -e "${YELLOW}Setup mode: Creating broken state...${NC}"
    if kubectl apply -f "$SETUP_FILE" 2>&1; then
        echo ""
        echo -e "${GREEN}Setup complete.${NC}"
        echo -e "Namespace: ${CYAN}${EXERCISE_NS}${NC}"
        echo ""
        echo "When done practicing, cleanup with:"
        echo -e "  ${CYAN}kubectl delete namespace ${EXERCISE_NS}${NC}"
        echo ""
        echo "Or verify your fix with:"
        echo -e "  ${CYAN}$0 ${EXERCISE_PATH} --check-only${NC}"
    else
        echo -e "${RED}Setup failed!${NC}"
        exit 1
    fi
    exit 0
fi

# Check-only mode
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "${YELLOW}Verifying your solution...${NC}"
    echo ""

    KUTTL_CMD="kubectl kuttl test ${DOMAIN_DIR} --config ${DOMAIN_DIR}/kuttl-test.yaml --test ${EXERCISE} --timeout ${TIMEOUT}"

    if $KUTTL_CMD; then
        echo ""
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ PASSED                                                     ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        EXIT_CODE=0
    else
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ✗ FAILED - Review the diff above                             ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        EXIT_CODE=1
    fi
    exit $EXIT_CODE
fi

# Full run mode
echo ""
echo -e "${BOLD}Workflow:${NC}"
echo "  1. Press Enter -> Setup creates broken state"
echo "  2. Fix the problem using kubectl, CLI tools, or UIs"
echo "  3. KUTTL continuously checks until pass or timeout"
echo "  4. Cleanup runs automatically (pass, fail, or Ctrl+C)"
echo ""
echo -e "${YELLOW}Press Enter to start timer...${NC}"

# Determine if we should wait for user input (use same logic as INTERACTIVE_MODE)
WAIT_FOR_INPUT=false
if [[ "$FORCE_INTERACTIVE" == "true" ]]; then
    WAIT_FOR_INPUT=true
elif [[ "$FORCE_INTERACTIVE" == "false" ]]; then
    WAIT_FOR_INPUT=false
elif [ -t 0 ]; then
    WAIT_FOR_INPUT=true
fi

if [[ "$WAIT_FOR_INPUT" == "true" ]]; then
    read -r </dev/tty 2>/dev/null || read -r
else
    echo -e "${YELLOW}(non-interactive) continuing...${NC}"
    sleep 1
fi

CLEANUP_ON_EXIT=true
trap cleanup_all EXIT
trap on_interrupt INT TERM

echo -e "${YELLOW}Creating broken state...${NC}"

# Apply setup - retry once if CRDs need time to establish
if ! kubectl apply -f "$SETUP_FILE" 2>&1; then
    echo -e "${YELLOW}Waiting for CRDs to establish...${NC}"
    
    # Wait for any CRDs in the setup file to be established
    crds=$(grep -E "^kind: CustomResourceDefinition" -A5 "$SETUP_FILE" 2>/dev/null | grep "name:" | awk '{print $2}' || true)
    for crd in $crds; do
        kubectl wait --for=condition=Established "crd/${crd}" --timeout=30s 2>/dev/null || true
    done
    
    sleep 2
    
    # Retry apply
    if ! kubectl apply -f "$SETUP_FILE" 2>&1; then
        echo -e "${RED}Setup failed!${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Setup complete. Fix the problem now!${NC}"
echo ""

# Load step descriptions
# keys are step numbers, so a plain indexed array works on bash 3.2
STEP_DESC=()
if [[ -f "${EXERCISE_DIR}/steps.txt" ]]; then
    while IFS=: read -r num desc; do
        # Skip empty lines or lines without valid step numbers
        [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]] && continue
        STEP_DESC[num]="$desc"
    done < "${EXERCISE_DIR}/steps.txt"
fi

# Count total steps
TOTAL_STEPS=$(find "$EXERCISE_DIR" -maxdepth 1 -name "*-assert.yaml" 2>/dev/null | wc -l | tr -d ' ')
CURRENT_STEP=0

KUTTL_STATUS=$(mktemp)
KUTTL_CMD="kubectl kuttl test ${DOMAIN_DIR} --config ${DOMAIN_DIR}/kuttl-test.yaml --test ${EXERCISE} --timeout ${TIMEOUT}"

# Determine interactive mode: --interactive/--non-interactive flags override TTY detection
if [[ "$FORCE_INTERACTIVE" == "true" ]]; then
    INTERACTIVE_MODE=true
elif [[ "$FORCE_INTERACTIVE" == "false" ]]; then
    INTERACTIVE_MODE=false
elif [ -t 0 ]; then
    INTERACTIVE_MODE=true
else
    INTERACTIVE_MODE=false
fi

# Non-interactive mode: use shorter KUTTL timeout with retry loop
# This allows the auto-fixer time to apply solutions between retries
if [[ "$INTERACTIVE_MODE" == "false" ]]; then
    KUTTL_ATTEMPT_TIMEOUT=30
    KUTTL_CMD="kubectl kuttl test ${DOMAIN_DIR} --config ${DOMAIN_DIR}/kuttl-test.yaml --test ${EXERCISE} --timeout ${KUTTL_ATTEMPT_TIMEOUT}"
fi

echo -e "${CYAN}Checking assertions...${NC}"
echo ""

START_TIME=$(date +%s)

# Timer function
show_timer() {
    local start=$1
    local timeout=$2
    local step_info="$3"
    while true; do
        local elapsed=$(($(date +%s) - start))
        local remaining=$((timeout - elapsed))
        [[ $remaining -lt 0 ]] && remaining=0

        local color="$GREEN"
        [[ $remaining -lt 120 ]] && color="$YELLOW"
        [[ $remaining -lt 60 ]] && color="$RED"

        local timer_text
        timer_text=$(printf "%02d:%02d" $((remaining / 60)) $((remaining % 60)))
        printf "\r${YELLOW}⏳ %s${NC} ${color}[${timer_text}]${NC}  " "$step_info"
        sleep 1
    done
}

# Function to run KUTTL once with output processing (for interactive mode)
run_kuttl_interactive() {
    # Start timer
    show_timer "$START_TIME" "$TIMEOUT" "Step 1/${TOTAL_STEPS}: Waiting for fix..." &
    TIMER_PID=$!

    # Process KUTTL output
    $KUTTL_CMD 2>&1 | while IFS= read -r line; do
        # Verbose mode
        if [[ "$VERBOSE" == "true" ]]; then
            printf "\r%80s\r" " "
            echo "$line"
            continue
        fi

        # Skip noise
        if [[ "$line" =~ "running command:" ]] || [[ "$line" =~ ^[[:space:]]*\]$ ]]; then
            continue
        fi

        # Step completed
        if [[ "$line" =~ "test step completed" ]]; then
            step_num=$(echo "$line" | sed -n 's/.*test step completed \([0-9]*\).*/\1/p')

            # Kill old timer, clear line
            kill "$TIMER_PID" 2>/dev/null || true
            printf "\r%80s\r" " "

            step_desc="${STEP_DESC[$step_num]:-}"
            if [[ -n "$step_desc" ]]; then
                echo -e "${GREEN}✓ Step $((step_num + 1))/${TOTAL_STEPS}:${step_desc}${NC}"
            else
                echo -e "${GREEN}✓ Step $((step_num + 1))/${TOTAL_STEPS} passed${NC}"
            fi

            # Parse assert file
            assert_file=""
            for f in "${EXERCISE_DIR}/0${step_num}-assert.yaml" "${EXERCISE_DIR}/${step_num}-assert.yaml"; do
                if [[ -f "$f" ]]; then
                    assert_file="$f"
                    break
                fi
            done
            if [[ -n "$assert_file" ]]; then
                "${SCRIPT_DIR}/parse-assert.sh" "$assert_file"
            fi

            CURRENT_STEP=$((step_num + 1))

            # Start new timer for next step
            if [[ $CURRENT_STEP -lt $TOTAL_STEPS ]]; then
                show_timer "$START_TIME" "$TIMEOUT" "Step $((CURRENT_STEP + 1))/${TOTAL_STEPS}: Waiting for fix..." &
                TIMER_PID=$!
            fi
            continue
        fi

        # Step failed
        if [[ "$line" =~ "test step failed" ]]; then
            kill "$TIMER_PID" 2>/dev/null || true
            printf "\r%80s\r" " "
            echo -e "${RED}✗ Step $((CURRENT_STEP + 1))/${TOTAL_STEPS} timed out${NC}"

            echo -e "${YELLOW}--- Debug Info ---${NC}"
            if [[ "$DOMAIN" == "1-gitops" ]]; then
                echo "ArgoCD Applications:"
                kubectl get applications -n argocd 2>/dev/null || true
                echo "Argo Rollouts:"
                kubectl get rollouts -A 2>/dev/null || true
            elif [[ "$DOMAIN" == "2-apis" ]]; then
                echo "CRDs:"
                kubectl get crd | grep cnpe 2>/dev/null || true
            elif [[ "$DOMAIN" == "3-observability" ]]; then
                echo "Monitoring Pods:"
                kubectl get pods -n monitoring 2>/dev/null || true
                echo "Prometheus Rules:"
                kubectl get prometheusrules -A 2>/dev/null || true
            elif [[ "$DOMAIN" == "5-security" ]]; then
                echo "RBAC Issues (Events):"
                kubectl get events -A --field-selector reason=FailedCreate 2>/dev/null | tail -n 5 || true
            fi

            if [[ -n "$EXERCISE_NS" ]]; then
                echo "Recent Events in ${EXERCISE_NS}:"
                kubectl get events --sort-by='.lastTimestamp' -n "$EXERCISE_NS" 2>/dev/null | tail -n 10 || true
            fi
            echo -e "${YELLOW}------------------${NC}"

            continue
        fi

        # Final results
        if [[ "$line" =~ ^---\ (PASS|FAIL) ]]; then
            kill "$TIMER_PID" 2>/dev/null || true
            printf "\r%80s\r" " "
            echo "$line"
            continue
        fi
    done
    PIPE_STATUS=${PIPESTATUS[0]}

    # Cleanup timer
    kill "$TIMER_PID" 2>/dev/null || true
    TIMER_PID=""
    printf "\r%80s\r" " "

    return "$PIPE_STATUS"
}

# Function to run KUTTL with retry loop (for non-interactive/CI mode)
run_kuttl_with_retry() {
    local max_elapsed=$TIMEOUT
    local retry_delay=5

    echo -e "${CYAN}Waiting for solution (timeout: ${max_elapsed}s)...${NC}"

    while true; do
        local now
        now=$(date +%s)
        local elapsed=$((now - START_TIME))
        local remaining=$((max_elapsed - elapsed))

        if [[ $remaining -le 0 ]]; then
            echo ""
            echo -e "${RED}Timeout reached${NC}"
            return 1
        fi

        # Show progress on same line
        printf "\r${YELLOW}⏳ Checking... [%02d:%02d remaining]${NC}  " $((remaining / 60)) $((remaining % 60))

        # Run KUTTL quietly
        if $KUTTL_CMD >/dev/null 2>&1; then
            printf "\r%60s\r" " "
            echo -e "${GREEN}--- PASS: kuttl${NC}"
            return 0
        fi

        sleep $retry_delay
    done
}

# Run KUTTL based on mode
if [[ "$INTERACTIVE_MODE" == "true" ]]; then
    if run_kuttl_interactive; then
        echo 0 > "$KUTTL_STATUS"
    else
        echo 1 > "$KUTTL_STATUS"
    fi
else
    # Non-interactive mode: retry until success or timeout
    if run_kuttl_with_retry; then
        echo 0 > "$KUTTL_STATUS"
    else
        echo -e "${RED}--- FAIL: kuttl${NC}"
        echo 1 > "$KUTTL_STATUS"
    fi
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

KUTTL_EXIT=$(cat "$KUTTL_STATUS" 2>/dev/null || echo "1")

echo ""
if [[ "$KUTTL_EXIT" == "0" ]]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    printf "${GREEN}║  ✓ PASSED in %d:%02d                                            ║${NC}\n" $((ELAPSED / 60)) $((ELAPSED % 60))
    if [[ $ELAPSED -le 420 ]]; then
        echo -e "${GREEN}║  Within 7-minute exam target!                                 ║${NC}"
    else
        echo -e "${YELLOW}║  Over 7-minute target - practice more!                        ║${NC}"
    fi
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    printf "${RED}║  ✗ FAILED after %d:%02d                                         ║${NC}\n" $((ELAPSED / 60)) $((ELAPSED % 60))
    echo -e "${RED}║  Review the errors above                                      ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    EXIT_CODE=1
fi

exit $EXIT_CODE
