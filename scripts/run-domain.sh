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
CHALLENGES_DIR="${SCRIPT_DIR}/../challenges"
RUN_EXERCISE="${SCRIPT_DIR}/run-exercise.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Domain descriptions
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
        *) echo "Unknown Domain" ;;
    esac
}

usage() {
    cat <<'USAGE_EOF'
Usage: run-domain.sh <domain> [options]

Run challenges within a domain with navigation between tasks.

Examples:
  run-domain.sh 1-gitops
  run-domain.sh 4-architecture --timeout 300

Options:
  --timeout N    Override timeout per challenge (default: from kuttl-test.yaml)
  --start N      Start at challenge number N (1-indexed)

Navigation (during session):
  n/Enter  Next challenge
  p        Previous challenge
  g N      Go to challenge N
  l        List all challenges
  q        Quit session
  r        Repeat current challenge

Available domains:
USAGE_EOF
    # List available domains
    for d in "$CHALLENGES_DIR"/*/; do
        domain=$(basename "$d")
        count=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        [[ $count -gt 0 ]] && echo "  $domain ($count challenges)"
    done
    exit "${1:-1}"
}

# Handle help before requiring domain
[[ $# -lt 1 ]] && usage 1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

DOMAIN="$1"
TIMEOUT=""
START_AT=1

shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            [[ -n "${2:-}" ]] || { echo "ERROR: --timeout requires a value" >&2; usage 1; }
            [[ "${2}" =~ ^[0-9]+$ ]] || { echo "ERROR: --timeout must be an integer (seconds)" >&2; usage 1; }
            TIMEOUT="$2"; shift 2
            ;;
        --start)
            [[ -n "${2:-}" ]] || { echo "ERROR: --start requires a value" >&2; usage 1; }
            [[ "${2}" =~ ^[0-9]+$ ]] || { echo "ERROR: --start must be an integer" >&2; usage 1; }
            START_AT="$2"; shift 2
            ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1"; usage 1 ;;
    esac
done

DOMAIN_DIR="${CHALLENGES_DIR}/${DOMAIN}"

if [[ ! -d "$DOMAIN_DIR" ]]; then
    echo -e "${RED}Domain not found: ${DOMAIN}${NC}"
    echo ""
    echo "Available domains:"
    for d in "$CHALLENGES_DIR"/*/; do
        domain=$(basename "$d")
        count=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        [[ $count -gt 0 ]] && echo "  $domain"
    done
    exit 1
fi

# Gather challenges in this domain
CHALLENGES=()
while IFS= read -r dir; do
    name=$(basename "$dir")
    # Skip if it's not a challenge directory (has no setup.yaml or assert files)
    if [[ -f "${dir}/setup.yaml" ]] || ls "${dir}"/*-assert.yaml >/dev/null 2>&1; then
        CHALLENGES+=("$name")
    fi
done < <(find "$DOMAIN_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#CHALLENGES[@]} -eq 0 ]]; then
    echo -e "${RED}No challenges found in domain: ${DOMAIN}${NC}"
    exit 1
fi

# Track results
# indexed by position in CHALLENGES - bash 3.2 has no associative arrays
RESULTS=()
CURRENT_IDX=$((START_AT - 1))
TOTAL=${#CHALLENGES[@]}
EXAM_START=$(date +%s)

# Validate start index
if [[ $CURRENT_IDX -lt 0 ]] || [[ $CURRENT_IDX -ge $TOTAL ]]; then
    echo -e "${RED}Invalid start index: ${START_AT}. Must be 1-${TOTAL}${NC}"
    exit 1
fi

show_header() {
    clear
    local elapsed=$(($(date +%s) - EXAM_START))
    local elapsed_fmt
    elapsed_fmt=$(printf "%02d:%02d" $((elapsed / 60)) $((elapsed % 60)))

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${BLUE}║${NC} ${BOLD}%-71s${NC} ${BLUE}║${NC}\n" "Domain: ${DOMAIN}"
    printf "${BLUE}║${NC} ${CYAN}%-71s${NC} ${BLUE}║${NC}\n" "$(get_domain_desc "$DOMAIN")"
    printf "${BLUE}║${NC} ${CYAN}%-71s${NC} ${BLUE}║${NC}\n" "Progress: $((CURRENT_IDX + 1))/${TOTAL} | Elapsed: ${elapsed_fmt}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_challenge_list() {
    show_header
    echo -e "${BOLD}Challenges in ${DOMAIN}:${NC}"
    echo ""

    for i in "${!CHALLENGES[@]}"; do
        local num=$((i + 1))
        local name="${CHALLENGES[$i]}"
        local status="${RESULTS[$i]:-pending}"
        local marker=" "
        local color="$NC"

        if [[ $i -eq $CURRENT_IDX ]]; then
            marker=">"
            color="$BOLD"
        fi

        case "$status" in
            "PASS") status_icon="${GREEN}✓${NC}" ;;
            "FAIL") status_icon="${RED}✗${NC}" ;;
            "SKIP") status_icon="${YELLOW}○${NC}" ;;
            *) status_icon="${DIM}·${NC}" ;;
        esac

        printf " %s ${color}%2d. %-40s${NC} %b\n" "$marker" "$num" "$name" "$status_icon"
    done
    echo ""
}

show_menu() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Commands:${NC} [n]ext  [p]rev  [g N]oto  [l]ist  [r]epeat  [s]kip  [q]uit"
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────────${NC}"
}

run_challenge() {
    local challenge="${CHALLENGES[$CURRENT_IDX]}"
    local path="${DOMAIN}/${challenge}"

    echo -e "${CYAN}Starting: ${path}${NC}"
    echo ""

    local cmd=("$RUN_EXERCISE" "$path" "--interactive")
    [[ -n "$TIMEOUT" ]] && cmd+=("--timeout" "$TIMEOUT")

    if "${cmd[@]}"; then
        RESULTS[CURRENT_IDX]="PASS"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 130 ]]; then
            # Ctrl+C - don't mark as failed
            return 130
        fi
        RESULTS[CURRENT_IDX]="FAIL"
        return 1
    fi
}

show_summary() {
    local elapsed=$(($(date +%s) - EXAM_START))
    local elapsed_fmt
    elapsed_fmt=$(printf "%02d:%02d" $((elapsed / 60)) $((elapsed % 60)))

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Domain Summary: ${DOMAIN}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"

    local passed=0
    local failed=0
    local skipped=0

    printf "%-40s %s\n" "Challenge" "Status"
    echo "────────────────────────────────────────────────────────"

    for i in "${!CHALLENGES[@]}"; do
        local name="${CHALLENGES[$i]}"
        local status="${RESULTS[$i]:-pending}"
        local status_text=""

        case "$status" in
            "PASS")
                status_text="${GREEN}PASS${NC}"
                ((passed++))
                ;;
            "FAIL")
                status_text="${RED}FAIL${NC}"
                ((failed++))
                ;;
            "SKIP")
                status_text="${YELLOW}SKIP${NC}"
                ((skipped++))
                ;;
            *)
                status_text="${DIM}--${NC}"
                ;;
        esac

        printf "%-40s %b\n" "$name" "$status_text"
    done

    echo "────────────────────────────────────────────────────────"
    local completed=$((passed + failed))
    local score=0
    [[ $completed -gt 0 ]] && score=$((passed * 100 / completed))

    echo -e "Passed: ${GREEN}${passed}${NC}  Failed: ${RED}${failed}${NC}  Skipped: ${YELLOW}${skipped}${NC}"
    echo -e "Score: ${passed}/${completed} (${score}%)"
    echo -e "Total Time: ${elapsed_fmt}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
}

# Main loop
while true; do
    show_challenge_list
    show_menu

    echo ""
    echo -ne "${YELLOW}Command (or Enter to start #$((CURRENT_IDX + 1))): ${NC}"

    read -r cmd arg </dev/tty 2>/dev/null || read -r cmd arg

    case "$cmd" in
        ""|n|N|next)
            # Run current challenge, then advance
            if run_challenge; then
                echo ""
                echo -e "${GREEN}Challenge passed!${NC}"
            else
                if [[ $? -eq 130 ]]; then
                    echo ""
                    echo -e "${YELLOW}Challenge interrupted.${NC}"
                else
                    echo ""
                    echo -e "${RED}Challenge failed.${NC}"
                fi
            fi

            # Auto-advance if not at end
            if [[ $((CURRENT_IDX + 1)) -lt $TOTAL ]]; then
                ((CURRENT_IDX++))
                echo ""
                echo -e "${CYAN}Press Enter to continue to next challenge...${NC}"
                read -r </dev/tty 2>/dev/null || read -r
            else
                echo ""
                echo -e "${GREEN}Completed all challenges in domain!${NC}"
                echo ""
                echo -ne "${YELLOW}Press Enter to see summary...${NC}"
                read -r </dev/tty 2>/dev/null || read -r
                show_summary
                exit 0
            fi
            ;;
        p|P|prev)
            if [[ $CURRENT_IDX -gt 0 ]]; then
                ((CURRENT_IDX--))
            else
                echo -e "${RED}Already at first challenge.${NC}"
                sleep 1
            fi
            ;;
        g|G|goto)
            if [[ -n "$arg" ]] && [[ "$arg" =~ ^[0-9]+$ ]]; then
                target=$((arg - 1))
                if [[ $target -ge 0 ]] && [[ $target -lt $TOTAL ]]; then
                    CURRENT_IDX=$target
                else
                    echo -e "${RED}Invalid challenge number. Use 1-${TOTAL}${NC}"
                    sleep 1
                fi
            else
                echo -ne "${YELLOW}Go to challenge number: ${NC}"
                read -r num </dev/tty 2>/dev/null || read -r num
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    target=$((num - 1))
                    if [[ $target -ge 0 ]] && [[ $target -lt $TOTAL ]]; then
                        CURRENT_IDX=$target
                    else
                        echo -e "${RED}Invalid challenge number. Use 1-${TOTAL}${NC}"
                        sleep 1
                    fi
                fi
            fi
            ;;
        l|L|list)
            # Just redisplay (happens automatically)
            ;;
        r|R|repeat)
            if run_challenge; then
                echo ""
                echo -e "${GREEN}Challenge passed!${NC}"
            else
                if [[ $? -eq 130 ]]; then
                    echo ""
                    echo -e "${YELLOW}Challenge interrupted.${NC}"
                else
                    echo ""
                    echo -e "${RED}Challenge failed.${NC}"
                fi
            fi
            echo ""
            echo -ne "${YELLOW}Press Enter to continue...${NC}"
            read -r </dev/tty 2>/dev/null || read -r
            ;;
        s|S|skip)
            RESULTS[CURRENT_IDX]="SKIP"
            if [[ $((CURRENT_IDX + 1)) -lt $TOTAL ]]; then
                ((CURRENT_IDX++))
            else
                echo -e "${YELLOW}Skipped. At last challenge.${NC}"
                sleep 1
            fi
            ;;
        q|Q|quit|exit)
            show_summary
            exit 0
            ;;
        [0-9]*)
            # Direct number entry
            target=$((cmd - 1))
            if [[ $target -ge 0 ]] && [[ $target -lt $TOTAL ]]; then
                CURRENT_IDX=$target
            else
                echo -e "${RED}Invalid challenge number. Use 1-${TOTAL}${NC}"
                sleep 1
            fi
            ;;
        *)
            echo -e "${RED}Unknown command: ${cmd}${NC}"
            sleep 1
            ;;
    esac
done
