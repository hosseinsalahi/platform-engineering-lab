#!/usr/bin/env bash
# Timed practice-set runner
# Interactive exam navigation matching linux-battleground design

set -Eeuo pipefail

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "ERROR: bash >= 4 is required to run ${0##*/} (current: ${BASH_VERSION:-unknown})." >&2
    echo "On macOS: install newer bash via Homebrew and ensure it is first in PATH." >&2
    echo "Example: brew install bash && export PATH=\"/opt/homebrew/bin:$PATH\"" >&2
    exit 1
fi

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
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_EXERCISE="${SCRIPT_DIR}/run-exercise.sh"
CHALLENGES_DIR="${ROOT_DIR}/challenges"
CLUSTER_NAME="${CNPE_CLUSTER_NAME:-battleground}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    cat <<'USAGE_EOF'
Usage:
  run-exam.sh [--interactive|--non-interactive] list <exam>
  run-exam.sh [--interactive|--non-interactive] start <exam>
  run-exam.sh list <exam>
  run-exam.sh start <exam>

Examples:
  ./scripts/run-exam.sh list exam-1
  ./scripts/run-exam.sh start exam-2
  ./scripts/run-exam.sh start domain-gitops
USAGE_EOF
    exit "${1:-1}"
}

friendly_exam_ref() {
    local p="$1"
    local base
    base="$(basename "$p")"
    base="${base%.yaml}"
    base="${base%.yml}"
    echo "$base"
}

resolve_exam_file() {
    local exam_arg="$1"
    if [[ -z "${exam_arg}" ]]; then
        return 1
    fi
    if [[ -f "${exam_arg}" ]]; then
        echo "${exam_arg}"
        return 0
    fi

    local resolved=""
    local candidates=(
        "${exam_arg}"
        "${ROOT_DIR}/${exam_arg}"
        "${ROOT_DIR}/exams/${exam_arg}"
        "${ROOT_DIR}/exams/${exam_arg}.yaml"
        "${ROOT_DIR}/exams/${exam_arg}.yml"
        "${ROOT_DIR}/exams/exam-${exam_arg}.yaml"
        "${ROOT_DIR}/exams/domain-${exam_arg}.yaml"
    )
    local p
    for p in "${candidates[@]}"; do
        if [[ -f "${p}" ]]; then
            resolved="${p}"
            break
        fi
    done
    if [[ -z "${resolved}" ]]; then
        return 1
    fi
    echo "${resolved}"
}

INTERACTIVE_MODE="auto"
while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        -h|--help) usage 0 ;;
        --interactive) INTERACTIVE_MODE="true"; shift ;;
        --non-interactive) INTERACTIVE_MODE="false"; shift ;;
        --) shift; break ;;
        *) break ;;
    esac
done

[[ $# -lt 2 ]] && usage 1
MODE="$1"
EXAM_FILE="$(resolve_exam_file "$2" || true)"

[[ -n "${EXAM_FILE}" && -f "$EXAM_FILE" ]] || { echo "Exam not found: $2" >&2; exit 1; }
[[ -x "$RUN_EXERCISE" ]] || { echo "Missing runner: $RUN_EXERCISE" >&2; exit 1; }

is_interactive() {
    case "${INTERACTIVE_MODE:-auto}" in
        true) [[ -t 0 && -t 1 ]] ;;
        false) return 1 ;;
        *) [[ -t 0 && -t 1 ]] ;;
    esac
}

check_helm_release() {
    local name="$1" ns="$2"
    helm --kube-context "${KIND_CONTEXT}" status "$name" -n "$ns" >/dev/null 2>&1
}

check_kubectl_ok() {
    kubectl --context "${KIND_CONTEXT}" get nodes >/dev/null 2>&1
}

KIND_KUBECONFIG_TMP=""
cleanup_kind_kubeconfig() {
    if [[ -n "${KIND_KUBECONFIG_TMP:-}" && -f "${KIND_KUBECONFIG_TMP}" ]]; then
        rm -f "${KIND_KUBECONFIG_TMP}" >/dev/null 2>&1 || true
    fi
}
trap cleanup_kind_kubeconfig EXIT

ensure_kind_context() {
    if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KIND_CONTEXT}"; then
        return 0
    fi

    if ! command -v kind >/dev/null 2>&1; then
        return 1
    fi
    if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
        return 1
    fi

    # Avoid relying on the user's kubeconfig being writable or containing kind contexts.
    KIND_KUBECONFIG_TMP="$(mktemp "${TMPDIR:-/tmp}/kind-${CLUSTER_NAME}-kubeconfig.XXXXXX")"
    if ! kind get kubeconfig --name "${CLUSTER_NAME}" >"${KIND_KUBECONFIG_TMP}" 2>/dev/null; then
        return 1
    fi
    export KUBECONFIG="${KIND_KUBECONFIG_TMP}"

    kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KIND_CONTEXT}"
}

deployment_available() {
    local ns="$1" name="$2"
    kubectl --context "${KIND_CONTEXT}" wait --for=condition=Available=True --timeout=1s "deployment/${name}" -n "$ns" >/dev/null 2>&1
}

tool_installed() {
    local tool="$1"
    case "$tool" in
        argocd) check_helm_release argocd argocd ;;
        argo-rollouts) check_helm_release argo-rollouts argo-rollouts ;;
        tekton)
            kubectl --context "${KIND_CONTEXT}" get crd pipelineruns.tekton.dev >/dev/null 2>&1 && \
            kubectl --context "${KIND_CONTEXT}" get crd triggerbindings.triggers.tekton.dev >/dev/null 2>&1 && \
            kubectl --context "${KIND_CONTEXT}" -n tekton-pipelines get deploy tekton-pipelines-controller >/dev/null 2>&1 && \
            (
              (
                ! kubectl --context "${KIND_CONTEXT}" get validatingwebhookconfiguration validation.webhook.triggers.tekton.dev >/dev/null 2>&1 && \
                ! kubectl --context "${KIND_CONTEXT}" get validatingwebhookconfiguration config.webhook.triggers.tekton.dev >/dev/null 2>&1 && \
                ! kubectl --context "${KIND_CONTEXT}" get mutatingwebhookconfiguration webhook.triggers.tekton.dev >/dev/null 2>&1
              ) || deployment_available tekton-pipelines tekton-triggers-webhook
            )
            ;;
        kyverno) check_helm_release kyverno kyverno ;;
        gatekeeper) check_helm_release gatekeeper gatekeeper-system ;;
        prometheus-stack) check_helm_release prometheus-stack monitoring ;;
        jaeger) check_helm_release jaeger jaeger ;;
        crossplane) check_helm_release crossplane crossplane-system ;;
        istio) check_helm_release istio-base istio-system && check_helm_release istiod istio-system ;;
        external-secrets) check_helm_release external-secrets external-secrets ;;
        metrics-server) check_helm_release metrics-server kube-system ;;
        opencost) check_helm_release opencost opencost ;;
        *) return 0 ;;
    esac
}

wait_for_tool() {
    local tool="$1"
    local timeout_seconds="${2:-180}"
    local start
    start="$(date +%s)"

    while true; do
        if tool_installed "$tool"; then
            return 0
        fi
        if (( $(date +%s) - start >= timeout_seconds )); then
            return 1
        fi
        sleep 2
    done
}

ensure_exam_ready() {
    local exam_path="$1"
    local exam_ref
    exam_ref="$(friendly_exam_ref "$exam_path")"
    local missing=()
    local tools=() tools_out=""

    command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found" >&2; exit 1; }
    command -v helm >/dev/null 2>&1 || { echo "Error: helm not found" >&2; exit 1; }
    command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found" >&2; exit 1; }

    ensure_kind_context || true

    if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KIND_CONTEXT}"; then
        missing+=("kind cluster (context ${KIND_CONTEXT} not found)")
    elif ! check_kubectl_ok; then
        missing+=("kind cluster not reachable via kubectl (context ${KIND_CONTEXT})")
    fi

    if ! tools_out="$(python3 "${SCRIPT_DIR}/exam-tools.py" --exam "${exam_path}" --format lines)"; then
        echo "Error: failed to infer required tools from exam file: ${exam_path}" >&2
        exit 1
    fi
    mapfile -t tools <<<"$tools_out"
    if [[ ${#tools[@]} -eq 0 ]]; then
        echo "Error: failed to infer required tools from exam file: ${exam_path}" >&2
        exit 1
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        local t
        for t in "${tools[@]}"; do
            if ! tool_installed "$t"; then
                missing+=("$t")
            fi
        done
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "${YELLOW}Exam prerequisites missing:${NC}" >&2
    local item
    for item in "${missing[@]}"; do
        echo "  - $item" >&2
    done
    echo "" >&2

    if ! is_interactive; then
        echo "Provision with: just provision-exam ${exam_ref}" >&2
        exit 1
    fi

    if ! read -r -p "Provision required tools/cluster now? [y/N] " reply; then
        reply=""
    fi
    case "${reply:-}" in
        y|Y)
            bash "${ROOT_DIR}/scripts/provision-cluster-light.sh" --exam "${exam_path}"
            ensure_kind_context || true
            if ! check_kubectl_ok; then
                echo "Error: cluster still not reachable after provisioning." >&2
                exit 1
            fi
            for item in "${tools[@]}"; do
                if ! wait_for_tool "$item" 240; then
                    echo "Error: tool still missing after provisioning: $item" >&2
                    exit 1
                fi
            done
            return 0
            ;;
        *)
            echo "Aborted. Provision with: just provision-exam ${exam_ref}" >&2
            exit 1
            ;;
    esac
}

# Check for yq
if ! command -v yq &>/dev/null; then
    echo -e "${RED}Error: yq not found!${NC}"
    echo "Please install yq: brew install yq"
    exit 1
fi

# Only enforce cluster/tool readiness when actually starting an exam.
if [[ "$MODE" == "start" ]]; then
    ensure_exam_ready "$EXAM_FILE"
fi

# Parse exam YAML
EXAM_NAME=$(yq -r '.name // "Exam"' "$EXAM_FILE")
EXAM_TIME_MINUTES=$(yq -r '.totalMinutes // 120' "$EXAM_FILE")
PASSING_PERCENTAGE=67

# Read challenges into arrays
mapfile -t CHALLENGES < <(yq -r '.sections[].challenge' "$EXAM_FILE" 2>/dev/null || true)
mapfile -t OBJECTIVES < <(yq -r '.sections[].objective' "$EXAM_FILE" 2>/dev/null || true)
mapfile -t DOMAINS < <(yq -r '.sections[].domain' "$EXAM_FILE" 2>/dev/null || true)
mapfile -t SECTION_IDS < <(yq -r '.sections[].id' "$EXAM_FILE" 2>/dev/null || true)
mapfile -t MINUTES < <(yq -r '.sections[].minutes' "$EXAM_FILE" 2>/dev/null || true)

TOTAL_TASKS=${#CHALLENGES[@]}
PASSING_SCORE=$(( TOTAL_TASKS * PASSING_PERCENTAGE / 100 ))

# Track results
declare -A TASK_RESULTS

count_statuses() {
    PASSED_TASKS=0
    FAILED_TASKS=0
    SKIPPED_COUNT=0
    NOT_STARTED_COUNT=0

    local task_id
    for ((task_id = 1; task_id <= TOTAL_TASKS; task_id++)); do
        case "${TASK_RESULTS[$task_id]:-NOT STARTED}" in
            PASSED) PASSED_TASKS=$((PASSED_TASKS + 1)) ;;
            FAILED) FAILED_TASKS=$((FAILED_TASKS + 1)) ;;
            SKIPPED) SKIPPED_COUNT=$((SKIPPED_COUNT + 1)) ;;
            *) NOT_STARTED_COUNT=$((NOT_STARTED_COUNT + 1)) ;;
        esac
    done

    COMPLETED_TASKS=$((PASSED_TASKS + FAILED_TASKS))
}

# Function to display elapsed time
show_elapsed_time() {
    local current
    current=$(date +%s)
    local elapsed=$((current - START_TIME))
    local remaining=$((EXAM_TIME_MINUTES * 60 - elapsed))

    if [[ $remaining -lt 0 ]]; then
        remaining=0
    fi

    local hours=$((remaining / 3600))
    local minutes=$(( (remaining % 3600) / 60 ))
    local seconds=$((remaining % 60))

    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# Function to check if time is up
is_time_up() {
    local current
    current=$(date +%s)
    local elapsed=$((current - START_TIME))
    [[ $elapsed -ge $((EXAM_TIME_MINUTES * 60)) ]]
}

# Function to display visual timer bar
show_timer_bar() {
    local current
    current=$(date +%s)
    local elapsed=$((current - START_TIME))
    local total_seconds=$((EXAM_TIME_MINUTES * 60))
    local remaining=$((total_seconds - elapsed))

    if [[ $remaining -lt 0 ]]; then
        remaining=0
        elapsed=$total_seconds
    fi

    # Calculate percentage used
    local percent_used=$((elapsed * 100 / total_seconds))
    if [[ $percent_used -gt 100 ]]; then
        percent_used=100
    fi

    # Bar width (40 characters)
    local bar_width=40
    local filled=$((percent_used * bar_width / 100))
    local empty=$((bar_width - filled))

    # Build the bar
    local bar=""
    for ((b = 0; b < filled; b++)); do
        bar+="█"
    done
    for ((b = 0; b < empty; b++)); do
        bar+="░"
    done

    # Color based on time remaining
    local bar_color
    if [[ $percent_used -ge 90 ]]; then
        bar_color="${RED}"
    elif [[ $percent_used -ge 75 ]]; then
        bar_color="${YELLOW}"
    else
        bar_color="${GREEN}"
    fi

    # Format remaining time
    local hours=$((remaining / 3600))
    local minutes=$(( (remaining % 3600) / 60 ))
    local seconds=$((remaining % 60))
    local time_str
    printf -v time_str "%02d:%02d:%02d" $hours $minutes $seconds

    # Print the bar
    printf "  ${bar_color}[%s]${NC} %3d%% | %s remaining\n" "$bar" "$percent_used" "$time_str"
}

print_header() {
    echo ""
    echo -e "${BOLD}=== $EXAM_NAME ===${NC}"
    echo -e "Total time: ${EXAM_TIME_MINUTES} minutes"
    echo ""
}

list_sections() {
    print_header
    if [[ $TOTAL_TASKS -eq 0 ]]; then
        echo "No sections found."
        return 0
    fi
    local total=0
    for ((idx = 0; idx < TOTAL_TASKS; idx++)); do
        local mins="${MINUTES[$idx]:-0}"
        total=$((total + mins))
        printf "%02d. [%s] %s (%dm) - %s\n" "$((idx + 1))" "${DOMAINS[$idx]:-}" "${CHALLENGES[$idx]:-}" "$mins" "${OBJECTIVES[$idx]:-}"
    done
    echo ""
    echo "Planned minutes: $total (exam total: $EXAM_TIME_MINUTES)"
    return 0
}

run_exam() {
    clear

    # Display exam instructions
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          PLATFORM ENGINEER BATTLEGROUND                        ║${NC}"
    echo -e "${BOLD}║                  TIMED PRACTICE SET                            ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}PRACTICE SET INFORMATION:${NC}"
    echo -e "  - Total Tasks: ${BOLD}$TOTAL_TASKS${NC}"
    echo -e "  - Time Limit: ${BOLD}$EXAM_TIME_MINUTES minutes${NC}"
    echo -e "  - Passing Score: ${BOLD}$PASSING_SCORE/$TOTAL_TASKS tasks ($PASSING_PERCENTAGE%)${NC}"
    echo "  - Format: Performance-based (hands-on)"
    echo ""
    echo -e "${CYAN}INSTRUCTIONS:${NC}"
    echo "  1. You will be presented with $TOTAL_TASKS tasks"
    echo "  2. Each task must be completed in the Kubernetes cluster"
    echo "  3. Read each task description carefully"
    echo "  4. Complete the task requirements"
    echo "  5. Validate your work when ready"
    echo "  6. You can skip tasks and return later"
    echo "  7. Time will be tracked throughout the exam"
    echo ""
    echo -e "${CYAN}NAVIGATION:${NC}"
    echo "  [c] Complete task and validate"
    echo "  [s] Skip this task for now"
    echo "  [h] Show hints"
    echo "  [n] Next task"
    echo "  [p] Previous task"
    echo "  [j] Jump to task number"
    echo "  [l] List all tasks with status"
    echo "  [q] Quit exam (will score current progress)"
    echo ""
    echo -e "${YELLOW}Press ENTER to start the exam...${NC}"
    read -r

    START_TIME=$(date +%s)

    # Run exam with manual navigation
    local i=0
    while true; do
        # Check if we've gone past the end
        if [[ $i -ge $TOTAL_TASKS ]]; then
            break
        fi

        # Check if we've gone before the start
        if [[ $i -lt 0 ]]; then
            i=0
        fi

        local TASK_NUM=$((i + 1))
        local CHALLENGE="${CHALLENGES[$i]:-}"
        local OBJECTIVE="${OBJECTIVES[$i]:-}"
        local DOMAIN="${DOMAINS[$i]:-}"
        local SECTION_ID="${SECTION_IDS[$i]:-}"
        local TASK_MINUTES="${MINUTES[$i]:-0}"

        clear

        # Update terminal title with timer
        echo -ne "\033]0;Practice Set | Task $TASK_NUM/$TOTAL_TASKS | Time: $(show_elapsed_time)\007"

        # Check time
        if is_time_up; then
            echo -e "${RED}${BOLD}TIME'S UP!${NC}"
            echo ""
            echo "The exam time has expired. Moving to results..."
            sleep 3
            break
        fi

        # Display task header
        echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
        printf "${BOLD}║  Task %d of %d                                                    ║${NC}\n" "$TASK_NUM" "$TOTAL_TASKS"
        echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
        show_timer_bar
        echo ""

        # Display task info
        echo -e "${CYAN}Section:${NC}   $SECTION_ID"
        echo -e "${CYAN}Domain:${NC}    $DOMAIN"
        echo -e "${CYAN}Challenge:${NC} $CHALLENGE"
        echo -e "${CYAN}Objective:${NC} $OBJECTIVE"
        echo -e "${CYAN}Budget:${NC}    ${TASK_MINUTES} minutes"
        echo ""

        # Display README
        local CHALLENGE_DIR="${CHALLENGES_DIR}/${CHALLENGE}"
        local README_FILE="${CHALLENGE_DIR}/README.md"
        if [[ -f "$README_FILE" ]]; then
            echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
            cat "$README_FILE"
            echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
        else
            echo -e "${YELLOW}No README found for $CHALLENGE${NC}"
        fi

        echo ""
        echo "Options:"
        echo "  [c] Complete this task and validate"
        echo "  [s] Skip this task for now"
        echo "  [h] Show hints"
        echo "  [n] Next task"
        echo "  [p] Previous task"
        echo "  [j] Jump to task number"
        echo "  [l] List all tasks with status"
        echo "  [q] Quit exam (will score current progress)"
        echo ""
        echo -n "Your choice: "
        read -r choice

        case "$choice" in
            c|C)
                # Run validation using run-exercise.sh
                echo ""
                echo -e "${CYAN}Running validation...${NC}"
                echo ""

                local timeout_secs=$((TASK_MINUTES * 60))
                [[ $timeout_secs -eq 0 ]] && timeout_secs=420

                local cmd=("$RUN_EXERCISE" "$CHALLENGE" "--check-only")

                if "${cmd[@]}"; then
                    echo ""
                    echo -e "${GREEN}${BOLD}Task $TASK_NUM: PASSED${NC}"
                    TASK_RESULTS[$TASK_NUM]="PASSED"
                else
                    echo ""
                    echo -e "${RED}${BOLD}Task $TASK_NUM: FAILED${NC}"
                    echo "Review your work and try again if time permits."
                    TASK_RESULTS[$TASK_NUM]="FAILED"
                fi

                echo ""
                echo "Press ENTER to continue..."
                read -r
                i=$((i + 1))
                ;;
            s|S)
                echo -e "${YELLOW}Task skipped. You can return to it later.${NC}"
                TASK_RESULTS[$TASK_NUM]="SKIPPED"
                sleep 2
                i=$((i + 1))
                ;;
            h|H)
                local HINTS_FILE="${CHALLENGE_DIR}/steps.txt"
                if [[ -f "$HINTS_FILE" ]]; then
                    echo ""
                    echo -e "${CYAN}Hints:${NC}"
                    cat "$HINTS_FILE"
                else
                    echo "No hints available for this task."
                fi
                echo ""
                echo "Press ENTER to continue..."
                read -r
                # Stay on current task
                ;;
            n|N)
                # Next task
                if [[ $TASK_NUM -lt $TOTAL_TASKS ]]; then
                    echo -e "${CYAN}Moving to next task...${NC}"
                    i=$((i + 1))
                    sleep 1
                else
                    echo -e "${YELLOW}Already at last task.${NC}"
                    sleep 2
                fi
                ;;
            p|P)
                # Previous task
                if [[ $TASK_NUM -gt 1 ]]; then
                    echo -e "${CYAN}Going back to previous task...${NC}"
                    i=$((i - 1))
                    sleep 1
                else
                    echo -e "${YELLOW}Already at first task.${NC}"
                    sleep 2
                fi
                ;;
            j|J)
                # Jump to specific task
                echo ""
                echo -n "Enter task number (1-$TOTAL_TASKS): "
                read -r jump_num
                if [[ "$jump_num" =~ ^[0-9]+$ ]] && [[ $jump_num -ge 1 ]] && [[ $jump_num -le $TOTAL_TASKS ]]; then
                    echo -e "${CYAN}Jumping to task $jump_num...${NC}"
                    i=$((jump_num - 1))
                    sleep 1
                else
                    echo -e "${RED}Invalid task number. Staying on current task.${NC}"
                    sleep 2
                fi
                ;;
            l|L)
                # List all tasks with status
                clear
                echo -ne "\033]0;Practice Set | Task Overview | Time: $(show_elapsed_time)\007"
                echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${BOLD}║                    TASK STATUS OVERVIEW                        ║${NC}"
                echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
                show_timer_bar
                echo ""
                echo -e "${CYAN}Current Position: Task $TASK_NUM of $TOTAL_TASKS${NC}"
                echo ""
                echo "Task Status:"
                for ((j = 0; j < TOTAL_TASKS; j++)); do
                    local task_id=$((j + 1))
                    local status="${TASK_RESULTS[$task_id]:-NOT STARTED}"
                    local chal="${CHALLENGES[$j]:-}"
                    case "$status" in
                        PASSED)
                            echo -e "  ${GREEN}✓${NC} Task $task_id: $chal - ${GREEN}PASSED${NC}"
                            ;;
                        FAILED)
                            echo -e "  ${RED}✗${NC} Task $task_id: $chal - ${RED}FAILED${NC}"
                            ;;
                        SKIPPED)
                            echo -e "  ${YELLOW}○${NC} Task $task_id: $chal - ${YELLOW}SKIPPED${NC}"
                            ;;
                        *)
                            if [[ $task_id -eq $TASK_NUM ]]; then
                                echo -e "  ${CYAN}→${NC} Task $task_id: $chal - ${CYAN}CURRENT${NC}"
                            else
                                echo "    Task $task_id: $chal - NOT STARTED"
                            fi
                            ;;
                    esac
                done
                echo ""
                echo -e "${CYAN}Summary:${NC}"
                count_statuses
                echo "  Passed: $PASSED_TASKS"
                echo "  Failed: $FAILED_TASKS"
                echo "  Skipped: $SKIPPED_COUNT"
                echo "  Not started: $NOT_STARTED_COUNT"
                echo ""
                echo "Press ENTER to return to Task $TASK_NUM..."
                read -r
                # Stay on current task
                ;;
            q|Q)
                echo -e "${YELLOW}Quitting exam early...${NC}"
                break
                ;;
            *)
                echo "Invalid choice. Returning to task."
                sleep 2
                # Stay on current task
                ;;
        esac
    done

    # Display final results
    clear
    # Reset terminal title
    echo -ne "\033]0;Practice Set | Complete\007"
    END_TIME=$(date +%s)
    TOTAL_TIME=$((END_TIME - START_TIME))
    TIME_MINUTES=$((TOTAL_TIME / 60))

    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                        EXAM COMPLETE                           ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    count_statuses

    echo -e "${CYAN}EXAM SUMMARY:${NC}"
    echo "  - Exam: $EXAM_NAME"
    echo "  - Total Tasks: $TOTAL_TASKS"
    echo "  - Completed: $COMPLETED_TASKS"
    echo "  - Passed: $PASSED_TASKS"
    echo "  - Failed: $FAILED_TASKS"
    echo "  - Skipped: $SKIPPED_COUNT"
    echo "  - Not started: $NOT_STARTED_COUNT"
    echo "  - Time Used: $TIME_MINUTES minutes"
    echo ""

    echo -e "${CYAN}DETAILED RESULTS:${NC}"
    for ((i = 0; i < TOTAL_TASKS; i++)); do
        local TASK_NUM=$((i + 1))
        local CHALLENGE="${CHALLENGES[$i]:-}"
        local RESULT="${TASK_RESULTS[$TASK_NUM]:-NOT STARTED}"

        case "$RESULT" in
            PASSED)
                echo -e "  ${GREEN}✓${NC} Task $TASK_NUM: $CHALLENGE - ${GREEN}PASSED${NC}"
                ;;
            FAILED)
                echo -e "  ${RED}✗${NC} Task $TASK_NUM: $CHALLENGE - ${RED}FAILED${NC}"
                ;;
            SKIPPED)
                echo -e "  ${YELLOW}○${NC} Task $TASK_NUM: $CHALLENGE - ${YELLOW}SKIPPED${NC}"
                ;;
            *)
                echo "    Task $TASK_NUM: $CHALLENGE - NOT STARTED"
                ;;
        esac
    done
    echo ""

    # Calculate final score (with division by zero protection)
    local PERCENTAGE
    if [[ $TOTAL_TASKS -eq 0 ]]; then
        PERCENTAGE=0
    else
        PERCENTAGE=$((PASSED_TASKS * 100 / TOTAL_TASKS))
    fi

    echo -e "${BOLD}FINAL SCORE: $PASSED_TASKS/$TOTAL_TASKS ($PERCENTAGE%)${NC}"
    echo ""

    if [[ $PASSED_TASKS -ge $PASSING_SCORE ]]; then
        echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║                      CONGRATULATIONS!                          ║${NC}"
        echo -e "${GREEN}${BOLD}║                                                                ║${NC}"
        echo -e "${GREEN}${BOLD}║                       YOU PASSED!                              ║${NC}"
        echo -e "${GREEN}${BOLD}║                                                                ║${NC}"
        echo -e "${GREEN}${BOLD}║        All tasks completed within their time budget.           ║${NC}"
        echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}║                      EXAM NOT PASSED                           ║${NC}"
        echo -e "${RED}${BOLD}║                                                                ║${NC}"
        printf "${RED}${BOLD}║  Required: %d/%d tasks (%d%%)                                    ║${NC}\n" "$PASSING_SCORE" "$TOTAL_TASKS" "$PASSING_PERCENTAGE"
        printf "${RED}${BOLD}║  Your Score: %d/%d tasks (%d%%)                                   ║${NC}\n" "$PASSED_TASKS" "$TOTAL_TASKS" "$PERCENTAGE"
        echo -e "${RED}${BOLD}║                                                                ║${NC}"
        echo -e "${RED}${BOLD}║  Review the failed tasks and practice more!                   ║${NC}"
        echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    fi

    echo ""

    # Save results to file
    local RESULTS_FILE
    RESULTS_FILE="${SCRIPT_DIR}/exam-results-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "Practice Set Results"
        echo "======================"
        echo ""
        echo "Exam: $EXAM_NAME"
        echo "Date: $(date)"
        echo "Duration: $TIME_MINUTES minutes"
        echo ""
        echo "Score: $PASSED_TASKS/$TOTAL_TASKS ($PERCENTAGE%)"
        echo "Status: $(if [[ $PASSED_TASKS -ge $PASSING_SCORE ]]; then echo "PASSED"; else echo "FAILED"; fi)"
        echo ""
        echo "Task Results:"
        for ((i = 0; i < TOTAL_TASKS; i++)); do
            local TASK_NUM=$((i + 1))
            local CHALLENGE="${CHALLENGES[$i]:-}"
            local RESULT="${TASK_RESULTS[$TASK_NUM]:-NOT STARTED}"
            echo "  Task $TASK_NUM: $CHALLENGE - $RESULT"
        done
    } > "$RESULTS_FILE"

    echo "Exam Results saved to: $RESULTS_FILE"
    echo ""

    return 0
}

# Main
case "$MODE" in
    list)
        list_sections
        ;;
    start)
        run_exam
        ;;
    *)
        echo "Unknown mode: $MODE" >&2
        exit 2
        ;;
esac
