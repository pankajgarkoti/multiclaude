#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# MULTICLAUDE DEVELOPMENT LOOP
#
# Launches a coordinated tmux session with:
#   - Window 0: Supervisor Agent (coordinates workers, triggers QA)
#   - Window 1: QA Agent (waits for signal, runs quality checks)
#   - Windows 2+: Worker Agents (implement features in parallel)
#
# All agents communicate via file-based message passing.
# The supervisor orchestrates the workflow autonomously.
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:-.}"

# Resolve absolute path
if [[ -d "$PROJECT_PATH" ]]; then
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
else
    echo "Error: Project path does not exist: $PROJECT_PATH"
    exit 1
fi

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

print_banner() {
    printf "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║         MULTICLAUDE DEVELOPMENT LOOP                              ║
    ║         Autonomous Agents with Message Passing                    ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    printf "${NC}\n"
}

log_info() {
    printf "${BLUE}[$(date '+%H:%M:%S')]${NC} $1\n"
}

log_success() {
    printf "${GREEN}[$(date '+%H:%M:%S')]${NC} $1\n"
}

log_warn() {
    printf "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1\n"
}

log_error() {
    printf "${RED}[$(date '+%H:%M:%S')]${NC} $1\n"
}

check_dependencies() {
    local missing=()

    command -v tmux &>/dev/null || missing+=("tmux")
    command -v claude &>/dev/null || missing+=("claude")
    command -v git &>/dev/null || missing+=("git")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Please install:"
        for dep in "${missing[@]}"; do
            case "$dep" in
                tmux) echo "  - tmux: brew install tmux (macOS) or apt install tmux (Linux)" ;;
                claude) echo "  - claude: https://claude.ai/code" ;;
                git) echo "  - git: brew install git (macOS) or apt install git (Linux)" ;;
            esac
        done
        exit 1
    fi
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

count_features() {
    local features
    features=($(get_features))
    echo "${#features[@]}"
}

#───────────────────────────────────────────────────────────────────────────────
# Worktree Setup
#───────────────────────────────────────────────────────────────────────────────

setup_worktrees() {
    log_info "Setting up worktrees..."

    cd "$PROJECT_PATH"

    local features
    features=($(get_features))

    if [[ ${#features[@]} -eq 0 ]]; then
        log_error "No features found. Create specs/features/*.spec.md or specs/.features"
        exit 1
    fi

    log_info "Features: ${features[*]}"

    # Ensure we're on main
    git checkout main 2>/dev/null || git checkout -b main

    # Create worktrees directory
    mkdir -p worktrees

    for feature in "${features[@]}"; do
        local branch_name="feature/${feature}"
        local worktree_path="${PROJECT_PATH}/worktrees/feature-${feature}"

        log_info "Setting up: $feature"

        # Skip if worktree already exists
        if [[ -d "$worktree_path" ]]; then
            log_info "  Worktree already exists, skipping..."
            continue
        fi

        # Create branch if it doesn't exist
        if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
            git branch "${branch_name}"
            log_info "  Created branch: ${branch_name}"
        fi

        # Create worktree
        git worktree add "${worktree_path}" "${branch_name}"
        log_info "  Created worktree: ${worktree_path}"

        # Create .claude directory
        mkdir -p "${worktree_path}/.claude"

        # Copy MCP configuration
        if [[ -f "${PROJECT_PATH}/.mcp.json" ]]; then
            cp "${PROJECT_PATH}/.mcp.json" "${worktree_path}/.mcp.json"
        fi

        # Copy Claude settings
        if [[ -f "${PROJECT_PATH}/.claude/settings.json" ]]; then
            cp "${PROJECT_PATH}/.claude/settings.json" "${worktree_path}/.claude/settings.json"
        fi

        # Copy feature spec
        if [[ -f "${PROJECT_PATH}/specs/features/${feature}.spec.md" ]]; then
            cp "${PROJECT_PATH}/specs/features/${feature}.spec.md" "${worktree_path}/.claude/FEATURE_SPEC.md"
        fi

        # Copy CLAUDE.md if exists
        if [[ -f "${PROJECT_PATH}/CLAUDE.md" ]]; then
            cp "${PROJECT_PATH}/CLAUDE.md" "${worktree_path}/CLAUDE.md"
        fi

        # Initialize status log
        cat > "${worktree_path}/.claude/status.log" << EOF
# Claude Status Log - Feature: ${feature}
# Format: [TIMESTAMP] [STATUS] [MESSAGE]
# Status: PENDING | IN_PROGRESS | BLOCKED | TESTING | COMPLETE | FAILED

$(date -Iseconds) [PENDING] Worktree initialized, awaiting Claude instance
EOF

        log_success "  Setup complete for: $feature"
    done

    log_success "All worktrees created"
}

#───────────────────────────────────────────────────────────────────────────────
# Template Installation
#───────────────────────────────────────────────────────────────────────────────

install_templates() {
    log_info "Installing agent templates..."

    # Ensure .claude directory exists in main project
    mkdir -p "$PROJECT_PATH/.claude"

    # Install Supervisor template
    if [[ -f "$SCRIPT_DIR/templates/SUPERVISOR.md" ]]; then
        cp "$SCRIPT_DIR/templates/SUPERVISOR.md" "$PROJECT_PATH/.claude/SUPERVISOR.md"
        log_info "  Installed SUPERVISOR.md"
    fi

    # Install QA template
    if [[ -f "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" ]]; then
        cp "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" "$PROJECT_PATH/.claude/QA_INSTRUCTIONS.md"
        log_info "  Installed QA_INSTRUCTIONS.md"
    fi

    # Initialize supervisor inbox
    if [[ ! -f "$PROJECT_PATH/.claude/supervisor-inbox.md" ]]; then
        cat > "$PROJECT_PATH/.claude/supervisor-inbox.md" << 'EOF'
# Supervisor Inbox

Messages from QA agent will appear here.
EOF
    fi

    # Initialize QA inbox
    if [[ ! -f "$PROJECT_PATH/.claude/qa-inbox.md" ]]; then
        cat > "$PROJECT_PATH/.claude/qa-inbox.md" << 'EOF'
# QA Inbox

Commands from the Supervisor will appear here.
Wait for RUN_QA signal before starting tests.
EOF
    fi

    # Install WORKER.md to all worktrees
    if [[ -f "$SCRIPT_DIR/templates/WORKER.md" ]]; then
        for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
            if [[ -d "$worktree" ]]; then
                mkdir -p "$worktree/.claude"
                cp "$SCRIPT_DIR/templates/WORKER.md" "$worktree/.claude/WORKER.md"

                # Initialize worker inbox if not exists
                if [[ ! -f "$worktree/.claude/inbox.md" ]]; then
                    cat > "$worktree/.claude/inbox.md" << 'EOF'
# Worker Inbox

Commands from the Supervisor will appear here.
Check this file periodically for FIX_TASK commands.
EOF
                fi
            fi
        done
        log_info "  Installed WORKER.md to all worktrees"
    fi

    # Install STANDARDS.md if not exists
    if [[ ! -f "$PROJECT_PATH/specs/STANDARDS.md" ]]; then
        if [[ -f "$SCRIPT_DIR/templates/STANDARDS.template.md" ]]; then
            mkdir -p "$PROJECT_PATH/specs"
            cp "$SCRIPT_DIR/templates/STANDARDS.template.md" "$PROJECT_PATH/specs/STANDARDS.md"
            log_info "  Created specs/STANDARDS.md from template"
        fi
    fi

    log_success "Templates installed"
}

#───────────────────────────────────────────────────────────────────────────────
# Agent Launching
#───────────────────────────────────────────────────────────────────────────────

launch_agents() {
    log_info "Launching agents in tmux session: $SESSION_NAME"
    echo ""

    # Check if tmux session already exists
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log_warn "tmux session '$SESSION_NAME' already exists"
        read -p "Kill existing session and start fresh? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            tmux kill-session -t "$SESSION_NAME"
        else
            log_info "Attaching to existing session..."
            tmux attach -t "$SESSION_NAME"
            return 0
        fi
    fi

    cd "$PROJECT_PATH"

    #───────────────────────────────────────────────────────────────────────
    # Window 0: Supervisor Agent
    #───────────────────────────────────────────────────────────────────────
    log_info "Creating Window 0: Supervisor..."

    local supervisor_prompt="You are the SUPERVISOR AGENT. Read .claude/SUPERVISOR.md for your complete instructions. You coordinate all workers and the QA agent via file-based message passing. Start by reading your instructions, then monitor worker status logs."

    tmux new-session -d -s "$SESSION_NAME" -n "supervisor" "cd '$PROJECT_PATH' && claude --dangerously-skip-permissions"

    sleep 3
    tmux send-keys -t "$SESSION_NAME:supervisor" "$supervisor_prompt"
    sleep 0.5
    tmux send-keys -t "$SESSION_NAME:supervisor" C-m

    log_success "  Supervisor launched in window 0"

    #───────────────────────────────────────────────────────────────────────
    # Window 1: QA Agent
    #───────────────────────────────────────────────────────────────────────
    log_info "Creating Window 1: QA..."

    local qa_prompt="You are the QA AGENT. Read .claude/QA_INSTRUCTIONS.md for your complete instructions. You MUST WAIT for a RUN_QA signal in .claude/qa-inbox.md before running tests. Start by reading your instructions, then begin polling your inbox."

    tmux new-window -t "$SESSION_NAME" -n "qa" "cd '$PROJECT_PATH' && claude --dangerously-skip-permissions"

    sleep 3
    tmux send-keys -t "$SESSION_NAME:qa" "$qa_prompt"
    sleep 0.5
    tmux send-keys -t "$SESSION_NAME:qa" C-m

    log_success "  QA launched in window 1"

    #───────────────────────────────────────────────────────────────────────
    # Windows 2+: Worker Agents
    #───────────────────────────────────────────────────────────────────────
    local window_num=2

    for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')

            log_info "Creating Window $window_num: Worker ($feature)..."

            local worker_prompt="You are a WORKER AGENT implementing the '$feature' feature. Read .claude/WORKER.md for your complete instructions. Your spec is in .claude/FEATURE_SPEC.md. Log status to .claude/status.log. Check .claude/inbox.md periodically. Start by reading your instructions."

            tmux new-window -t "$SESSION_NAME" -n "$feature" "cd '$worktree' && claude --dangerously-skip-permissions"

            sleep 3
            tmux send-keys -t "$SESSION_NAME:$feature" "$worker_prompt"
            sleep 0.5
            tmux send-keys -t "$SESSION_NAME:$feature" C-m

            log_success "  Worker '$feature' launched in window $window_num"
            ((window_num++))

            sleep 1  # Stagger launches to avoid rate limits
        fi
    done

    echo ""
    log_success "All agents launched!"
    echo ""
    printf "${BOLD}tmux Session Structure:${NC}\n"
    printf "  Window 0: ${CYAN}supervisor${NC} - Coordinates workers and QA\n"
    printf "  Window 1: ${CYAN}qa${NC}         - Waits for RUN_QA signal\n"

    window_num=2
    for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')
            printf "  Window $window_num: ${CYAN}$feature${NC}   - Worker agent\n"
            ((window_num++))
        fi
    done

    echo ""
    printf "${BOLD}Communication Files:${NC}\n"
    printf "  Supervisor inbox: ${YELLOW}.claude/supervisor-inbox.md${NC}\n"
    printf "  QA inbox:         ${YELLOW}.claude/qa-inbox.md${NC}\n"
    printf "  Worker inboxes:   ${YELLOW}worktrees/feature-*/.claude/inbox.md${NC}\n"
    printf "  Worker status:    ${YELLOW}worktrees/feature-*/.claude/status.log${NC}\n"
    echo ""
    printf "${BOLD}To attach to the session:${NC}\n"
    printf "  ${GREEN}tmux attach -t $SESSION_NAME${NC}\n"
    echo ""
    printf "${BOLD}tmux shortcuts:${NC}\n"
    printf "  ${CYAN}Ctrl+b n${NC}  - Next window\n"
    printf "  ${CYAN}Ctrl+b p${NC}  - Previous window\n"
    printf "  ${CYAN}Ctrl+b 0${NC}  - Go to window 0 (Supervisor)\n"
    printf "  ${CYAN}Ctrl+b 1${NC}  - Go to window 1 (QA)\n"
    printf "  ${CYAN}Ctrl+b d${NC}  - Detach from session\n"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# Status Display
#───────────────────────────────────────────────────────────────────────────────

show_status() {
    echo ""
    printf "${BOLD}Agent Status:${NC}\n"
    echo "─────────────────────────────────────────────────────────────────"

    # Check if tmux session exists
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        printf "  tmux session: ${GREEN}$SESSION_NAME (running)${NC}\n"
    else
        printf "  tmux session: ${RED}$SESSION_NAME (not running)${NC}\n"
    fi
    echo ""

    # Check communication files
    printf "${BOLD}Communication Files:${NC}\n"

    if [[ -f "$PROJECT_PATH/.claude/supervisor-inbox.md" ]]; then
        local sup_inbox=$(wc -l < "$PROJECT_PATH/.claude/supervisor-inbox.md" | tr -d ' ')
        printf "  Supervisor inbox: ${GREEN}exists${NC} ($sup_inbox lines)\n"
    else
        printf "  Supervisor inbox: ${RED}missing${NC}\n"
    fi

    if [[ -f "$PROJECT_PATH/.claude/qa-inbox.md" ]]; then
        local qa_inbox=$(wc -l < "$PROJECT_PATH/.claude/qa-inbox.md" | tr -d ' ')
        printf "  QA inbox:         ${GREEN}exists${NC} ($qa_inbox lines)\n"
    else
        printf "  QA inbox:         ${RED}missing${NC}\n"
    fi
    echo ""

    # Worker status
    printf "${BOLD}Worker Status:${NC}\n"

    local total=0
    local complete=0
    local in_progress=0
    local blocked=0

    for worktree in "$PROJECT_PATH"/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')
            local log_file="$worktree/.claude/status.log"
            ((total++))

            if [[ -f "$log_file" ]]; then
                local last=$(grep -E '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' "$log_file" 2>/dev/null | tail -1)
                local status=$(echo "$last" | grep -oE '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' | tr -d '[]')
                local msg=$(echo "$last" | sed 's/.*\] //' | cut -c1-40)

                case "$status" in
                    COMPLETE)    color="${GREEN}"; ((complete++)) ;;
                    IN_PROGRESS) color="${YELLOW}"; ((in_progress++)) ;;
                    BLOCKED|FAILED) color="${RED}"; ((blocked++)) ;;
                    *)           color="${NC}" ;;
                esac

                printf "  %-15s ${color}%-12s${NC} %s\n" "$feature" "$status" "$msg"
            else
                printf "  %-15s ${RED}%-12s${NC}\n" "$feature" "NO_LOG"
            fi
        fi
    done

    echo "─────────────────────────────────────────────────────────────────"
    printf "  Total: $total | ${GREEN}Complete: $complete${NC} | ${YELLOW}In Progress: $in_progress${NC} | ${RED}Blocked: $blocked${NC}\n"
    echo ""

    # Check for completion markers
    if [[ -f "$PROJECT_PATH/.claude/PROJECT_COMPLETE" ]]; then
        printf "${GREEN}╔════════════════════════════════════════╗${NC}\n"
        printf "${GREEN}║         PROJECT COMPLETE!              ║${NC}\n"
        printf "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    elif [[ -f "$PROJECT_PATH/.claude/QA_COMPLETE" ]]; then
        printf "${GREEN}QA has passed. Awaiting final completion.${NC}\n"
    elif [[ -f "$PROJECT_PATH/.claude/QA_NEEDS_FIXES" ]]; then
        printf "${YELLOW}QA found issues. Workers should check their inboxes.${NC}\n"
    elif [[ -f "$PROJECT_PATH/.claude/ALL_MERGED" ]]; then
        printf "${CYAN}All features merged. QA should be running.${NC}\n"
    fi
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# Command-line Interface
#───────────────────────────────────────────────────────────────────────────────

print_usage() {
    echo "Usage: $0 <project-path> [options]"
    echo ""
    echo "Launches a coordinated multi-agent development session in tmux."
    echo ""
    echo "Arguments:"
    echo "  project-path      Path to the project directory"
    echo ""
    echo "Options:"
    echo "  --setup-only      Only setup worktrees and templates, don't launch agents"
    echo "  --status          Show current status and exit"
    echo "  --attach          Attach to existing tmux session"
    echo "  --help            Show this help message"
    echo ""
    echo "Session Structure:"
    echo "  Window 0: Supervisor (coordinates everything)"
    echo "  Window 1: QA (waits for signals, runs tests)"
    echo "  Window 2+: Workers (one per feature)"
    echo ""
    echo "Examples:"
    echo "  $0 ./my-project              # Launch full agent session"
    echo "  $0 ./my-project --status     # Check current status"
    echo "  $0 ./my-project --attach     # Attach to running session"
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────

# Parse options
SETUP_ONLY=false
STATUS_ONLY=false
ATTACH_ONLY=false
PROJECT_PATH_SET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-only)
            SETUP_ONLY=true
            shift
            ;;
        --status)
            STATUS_ONLY=true
            shift
            ;;
        --attach)
            ATTACH_ONLY=true
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            if [[ "$PROJECT_PATH_SET" == false ]]; then
                PROJECT_PATH="$1"
                PROJECT_PATH_SET=true
            fi
            shift
            ;;
    esac
done

# Resolve project path
if [[ -d "$PROJECT_PATH" ]]; then
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
else
    log_error "Project path does not exist: $PROJECT_PATH"
    exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_PATH")"
SESSION_NAME="claude-${PROJECT_NAME}"

print_banner

echo "Project: $PROJECT_NAME"
echo "Path:    $PROJECT_PATH"
echo ""

# Attach only mode
if [[ "$ATTACH_ONLY" == true ]]; then
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux attach -t "$SESSION_NAME"
    else
        log_error "No tmux session found: $SESSION_NAME"
        exit 1
    fi
    exit 0
fi

# Status only mode
if [[ "$STATUS_ONLY" == true ]]; then
    show_status
    exit 0
fi

# Check dependencies
check_dependencies

# Ensure .claude directory exists
mkdir -p "$PROJECT_PATH/.claude"

# Check for features
feature_count=$(count_features)

if [[ "$feature_count" -eq 0 ]]; then
    log_error "No features found."
    echo "Create feature specs in specs/features/*.spec.md"
    echo "Or list features in specs/.features (one per line)"
    exit 1
fi

log_success "Found $feature_count features"

# Check for worktrees
worktree_count=$(ls -d "$PROJECT_PATH"/worktrees/feature-* 2>/dev/null | wc -l | tr -d ' ')

if [[ "$worktree_count" -eq 0 ]]; then
    log_info "No worktrees found. Setting up..."
    setup_worktrees
fi

# Install templates
install_templates

# Setup only mode
if [[ "$SETUP_ONLY" == true ]]; then
    show_status
    echo "Setup complete. Run without --setup-only to launch agents."
    exit 0
fi

# Launch agents
launch_agents

# Ask to attach
echo ""
read -p "Attach to tmux session now? (Y/n): " attach_confirm
if [[ ! "$attach_confirm" =~ ^[Nn] ]]; then
    tmux attach -t "$SESSION_NAME"
fi
