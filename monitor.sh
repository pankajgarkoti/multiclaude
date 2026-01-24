#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# MULTICLAUDE MONITOR - Control Center (Window 0)
#
# This script runs inside tmux Window 0 and:
#   1. Sets up worktrees
#   2. Installs templates
#   3. Launches agent windows
#   4. Provides interactive monitoring
#═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$1"

if [[ -z "$PROJECT_PATH" ]] || [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: Invalid project path"
    exit 1
fi

cd "$PROJECT_PATH"

PROJECT_NAME="$(basename "$PROJECT_PATH")"
SESSION_NAME="claude-${PROJECT_NAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

#───────────────────────────────────────────────────────────────────────────────
# Helper Functions
#───────────────────────────────────────────────────────────────────────────────

print_banner() {
    clear
    printf "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║         MULTICLAUDE CONTROL CENTER                                ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    printf "${NC}"
    echo ""
    printf "  Project: ${BOLD}$PROJECT_NAME${NC}\n"
    printf "  Path:    ${DIM}$PROJECT_PATH${NC}\n"
    echo ""
}

log_step() {
    printf "${BLUE}▶${NC} $1\n"
}

log_success() {
    printf "${GREEN}✓${NC} $1\n"
}

log_warn() {
    printf "${YELLOW}!${NC} $1\n"
}

log_error() {
    printf "${RED}✗${NC} $1\n"
}

print_separator() {
    printf "${DIM}─────────────────────────────────────────────────────────────────${NC}\n"
}

#───────────────────────────────────────────────────────────────────────────────
# Feature Discovery
#───────────────────────────────────────────────────────────────────────────────

get_features() {
    local features=()

    if [[ -f "$PROJECT_PATH/specs/.features" ]]; then
        while IFS= read -r feature; do
            [[ -n "$feature" ]] && [[ ! "$feature" =~ ^# ]] && features+=("$feature")
        done < "$PROJECT_PATH/specs/.features"
    elif [[ -d "$PROJECT_PATH/specs/features" ]]; then
        for spec in "$PROJECT_PATH/specs/features"/*.spec.md; do
            if [[ -f "$spec" ]]; then
                features+=("$(basename "$spec" .spec.md)")
            fi
        done
    fi

    echo "${features[@]}"
}

#───────────────────────────────────────────────────────────────────────────────
# Setup Functions
#───────────────────────────────────────────────────────────────────────────────

setup_worktrees() {
    log_step "Setting up git worktrees..."

    local features=($(get_features))

    if [[ ${#features[@]} -eq 0 ]]; then
        log_error "No features found in specs/features/*.spec.md or specs/.features"
        return 1
    fi

    printf "  Features: ${CYAN}${features[*]}${NC}\n"

    # Ensure we're on main
    git checkout main 2>/dev/null || git checkout -b main 2>/dev/null

    # Create worktrees directory
    mkdir -p worktrees

    for feature in "${features[@]}"; do
        local branch_name="feature/${feature}"
        local worktree_path="${PROJECT_PATH}/worktrees/feature-${feature}"

        if [[ -d "$worktree_path" ]]; then
            printf "  ${DIM}%-15s already exists${NC}\n" "$feature"
            continue
        fi

        # Create branch if it doesn't exist
        if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
            git branch "${branch_name}" 2>/dev/null
        fi

        # Create worktree
        git worktree add "${worktree_path}" "${branch_name}" 2>/dev/null

        # Setup worktree .claude directory
        mkdir -p "${worktree_path}/.claude"

        # Copy configs
        [[ -f "${PROJECT_PATH}/.mcp.json" ]] && cp "${PROJECT_PATH}/.mcp.json" "${worktree_path}/.mcp.json"
        [[ -f "${PROJECT_PATH}/.claude/settings.json" ]] && cp "${PROJECT_PATH}/.claude/settings.json" "${worktree_path}/.claude/settings.json"
        [[ -f "${PROJECT_PATH}/CLAUDE.md" ]] && cp "${PROJECT_PATH}/CLAUDE.md" "${worktree_path}/CLAUDE.md"

        # Copy feature spec
        if [[ -f "${PROJECT_PATH}/specs/features/${feature}.spec.md" ]]; then
            cp "${PROJECT_PATH}/specs/features/${feature}.spec.md" "${worktree_path}/.claude/FEATURE_SPEC.md"
        fi

        # Initialize status log
        echo "$(date -Iseconds) [PENDING] Worktree initialized" > "${worktree_path}/.claude/status.log"

        printf "  ${GREEN}%-15s created${NC}\n" "$feature"
    done

    log_success "Worktrees ready"
}

install_templates() {
    log_step "Installing agent templates..."

    mkdir -p "$PROJECT_PATH/.claude"

    # Supervisor template
    if [[ -f "$SCRIPT_DIR/templates/SUPERVISOR.md" ]]; then
        cp "$SCRIPT_DIR/templates/SUPERVISOR.md" "$PROJECT_PATH/.claude/SUPERVISOR.md"
        printf "  ${GREEN}✓${NC} SUPERVISOR.md\n"
    fi

    # QA template
    if [[ -f "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" ]]; then
        cp "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" "$PROJECT_PATH/.claude/QA_INSTRUCTIONS.md"
        printf "  ${GREEN}✓${NC} QA_INSTRUCTIONS.md\n"
    fi

    # Initialize inboxes
    [[ ! -f "$PROJECT_PATH/.claude/supervisor-inbox.md" ]] && echo "# Supervisor Inbox" > "$PROJECT_PATH/.claude/supervisor-inbox.md"
    [[ ! -f "$PROJECT_PATH/.claude/qa-inbox.md" ]] && echo "# QA Inbox - Waiting for RUN_QA signal" > "$PROJECT_PATH/.claude/qa-inbox.md"

    # Worker templates
    if [[ -f "$SCRIPT_DIR/templates/WORKER.md" ]]; then
        for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
            if [[ -d "$worktree" ]]; then
                cp "$SCRIPT_DIR/templates/WORKER.md" "$worktree/.claude/WORKER.md"
                [[ ! -f "$worktree/.claude/inbox.md" ]] && echo "# Worker Inbox" > "$worktree/.claude/inbox.md"
            fi
        done
        printf "  ${GREEN}✓${NC} WORKER.md (all worktrees)\n"
    fi

    # Standards template
    if [[ ! -f "$PROJECT_PATH/specs/STANDARDS.md" ]] && [[ -f "$SCRIPT_DIR/templates/STANDARDS.template.md" ]]; then
        cp "$SCRIPT_DIR/templates/STANDARDS.template.md" "$PROJECT_PATH/specs/STANDARDS.md"
        printf "  ${GREEN}✓${NC} STANDARDS.md\n"
    fi

    log_success "Templates installed"
}

#───────────────────────────────────────────────────────────────────────────────
# Agent Launching
#───────────────────────────────────────────────────────────────────────────────

launch_agents() {
    log_step "Launching agents..."
    echo ""

    local window_num=1

    #─────────────────────────────────────────────────────────────────────
    # Window 1: Supervisor
    #─────────────────────────────────────────────────────────────────────
    printf "  Creating window $window_num: ${CYAN}supervisor${NC}..."

    tmux new-window -t "$SESSION_NAME" -n "supervisor" \
        "cd '$PROJECT_PATH' && claude --dangerously-skip-permissions"

    local supervisor_prompt="You are the SUPERVISOR AGENT. Read .claude/SUPERVISOR.md for your complete instructions. You coordinate all workers and the QA agent via file-based message passing. Start by reading your instructions, then monitor worker status logs at worktrees/feature-*/.claude/status.log"

    sleep 2
    tmux send-keys -t "$SESSION_NAME:supervisor" "$supervisor_prompt"
    sleep 0.3
    tmux send-keys -t "$SESSION_NAME:supervisor" C-m

    printf " ${GREEN}launched${NC}\n"
    ((window_num++))

    #─────────────────────────────────────────────────────────────────────
    # Window 2: QA
    #─────────────────────────────────────────────────────────────────────
    printf "  Creating window $window_num: ${CYAN}qa${NC}..."

    tmux new-window -t "$SESSION_NAME" -n "qa" \
        "cd '$PROJECT_PATH' && claude --dangerously-skip-permissions"

    local qa_prompt="You are the QA AGENT. Read .claude/QA_INSTRUCTIONS.md for your complete instructions. You MUST WAIT for a RUN_QA signal in .claude/qa-inbox.md before running any tests. Start by reading your instructions, then poll your inbox."

    sleep 2
    tmux send-keys -t "$SESSION_NAME:qa" "$qa_prompt"
    sleep 0.3
    tmux send-keys -t "$SESSION_NAME:qa" C-m

    printf " ${GREEN}launched${NC}\n"
    ((window_num++))

    #─────────────────────────────────────────────────────────────────────
    # Windows 3+: Workers
    #─────────────────────────────────────────────────────────────────────
    for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')

            printf "  Creating window $window_num: ${CYAN}$feature${NC} (worker)..."

            tmux new-window -t "$SESSION_NAME" -n "$feature" \
                "cd '$worktree' && claude --dangerously-skip-permissions"

            local worker_prompt="You are a WORKER AGENT implementing the '$feature' feature. Read .claude/WORKER.md for your complete instructions. Your feature spec is in .claude/FEATURE_SPEC.md. Log your status to .claude/status.log. Check .claude/inbox.md periodically for commands. Start by reading your instructions."

            sleep 2
            tmux send-keys -t "$SESSION_NAME:$feature" "$worker_prompt"
            sleep 0.3
            tmux send-keys -t "$SESSION_NAME:$feature" C-m

            printf " ${GREEN}launched${NC}\n"
            ((window_num++))

            sleep 1  # Stagger to avoid rate limits
        fi
    done

    echo ""
    log_success "All agents launched!"
}

#───────────────────────────────────────────────────────────────────────────────
# Status Display
#───────────────────────────────────────────────────────────────────────────────

show_status() {
    echo ""
    printf "${BOLD}Session Windows:${NC}\n"
    tmux list-windows -t "$SESSION_NAME" 2>/dev/null | while read line; do
        printf "  $line\n"
    done

    echo ""
    printf "${BOLD}Worker Status:${NC}\n"
    printf "  %-15s %-12s %s\n" "FEATURE" "STATUS" "MESSAGE"
    print_separator

    for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')
            local log="$worktree/.claude/status.log"

            if [[ -f "$log" ]]; then
                local last=$(grep -E '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' "$log" 2>/dev/null | tail -1)
                local status=$(echo "$last" | grep -oE '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' | tr -d '[]')
                local msg=$(echo "$last" | sed 's/.*\] //' | cut -c1-35)

                case "$status" in
                    COMPLETE)    color="${GREEN}" ;;
                    IN_PROGRESS) color="${YELLOW}" ;;
                    TESTING)     color="${CYAN}" ;;
                    BLOCKED|FAILED) color="${RED}" ;;
                    *)           color="${NC}"; status="PENDING" ;;
                esac

                printf "  %-15s ${color}%-12s${NC} %s\n" "$feature" "$status" "$msg"
            else
                printf "  %-15s ${RED}%-12s${NC}\n" "$feature" "NO_LOG"
            fi
        fi
    done

    echo ""

    # Check markers
    if [[ -f "$PROJECT_PATH/.claude/PROJECT_COMPLETE" ]]; then
        printf "${GREEN}██ PROJECT COMPLETE ██${NC}\n"
    elif [[ -f "$PROJECT_PATH/.claude/QA_COMPLETE" ]]; then
        printf "${GREEN}QA passed${NC}\n"
    elif [[ -f "$PROJECT_PATH/.claude/QA_NEEDS_FIXES" ]]; then
        printf "${YELLOW}QA needs fixes${NC}\n"
    elif [[ -f "$PROJECT_PATH/.claude/ALL_MERGED" ]]; then
        printf "${CYAN}All merged, QA pending${NC}\n"
    fi
}

show_help() {
    echo ""
    printf "${BOLD}Commands:${NC}\n"
    echo "  s, status     Show current status"
    echo "  w, watch      Watch status (auto-refresh)"
    echo "  l, logs       Tail worker status logs"
    echo "  m, messages   Tail message files"
    echo "  h, help       Show this help"
    echo "  q, quit       Exit monitor (agents keep running)"
    echo ""
    printf "${BOLD}tmux shortcuts:${NC}\n"
    echo "  Ctrl+b 1      Go to Supervisor"
    echo "  Ctrl+b 2      Go to QA"
    echo "  Ctrl+b 3+     Go to Workers"
    echo "  Ctrl+b n/p    Next/Previous window"
    echo "  Ctrl+b d      Detach (keeps session running)"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# Interactive Loop
#───────────────────────────────────────────────────────────────────────────────

interactive_loop() {
    print_separator
    printf "${BOLD}Monitor ready.${NC} Type ${CYAN}help${NC} for commands.\n"
    print_separator

    show_status

    while true; do
        echo ""
        printf "${CYAN}monitor>${NC} "
        read -r cmd args

        case "$cmd" in
            s|status)
                show_status
                ;;
            w|watch)
                watch -n 5 "$SCRIPT_DIR/multiclaude" status "$PROJECT_PATH"
                ;;
            l|logs)
                tail -f "$PROJECT_PATH"/worktrees/feature-*/.claude/status.log
                ;;
            m|messages)
                tail -f "$PROJECT_PATH"/.claude/*.md "$PROJECT_PATH"/worktrees/feature-*/.claude/inbox.md 2>/dev/null
                ;;
            h|help|"?")
                show_help
                ;;
            q|quit|exit)
                echo ""
                printf "${YELLOW}Exiting monitor. Agents continue running.${NC}\n"
                printf "Re-attach with: ${CYAN}tmux attach -t $SESSION_NAME${NC}\n"
                echo ""
                exit 0
                ;;
            "")
                # Empty input, just show prompt again
                ;;
            *)
                # Try to run as shell command
                eval "$cmd $args" 2>/dev/null || printf "${RED}Unknown command: $cmd${NC}\n"
                ;;
        esac
    done
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────

print_banner
print_separator

# Check for features
features=($(get_features))
if [[ ${#features[@]} -eq 0 ]]; then
    log_error "No features found!"
    echo ""
    echo "Create feature specs in:"
    echo "  - specs/features/*.spec.md"
    echo "  - OR specs/.features (one feature name per line)"
    echo ""
    echo "Then run this again."
    exit 1
fi

log_success "Found ${#features[@]} features: ${features[*]}"
echo ""

# Setup
setup_worktrees
echo ""

install_templates
echo ""

# Launch agents
launch_agents
echo ""

print_separator

# Enter interactive mode
interactive_loop
