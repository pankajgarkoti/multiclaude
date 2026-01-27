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

# Source shared phases library
source "$SCRIPT_DIR/phases.sh"

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
    printf "  Project: ${BOLD}%s${NC}\n" "$PROJECT_NAME"
    printf "  Path:    ${DIM}%s${NC}\n" "$PROJECT_PATH"
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
# Mailbox Router
#───────────────────────────────────────────────────────────────────────────────

watch_mailbox() {
    local mailbox="$PROJECT_PATH/.multiclaude/mailbox"
    local processed_count=0

    while true; do
        if [[ -f "$mailbox" ]]; then
            # Count messages by counting "--- MESSAGE ---" markers
            local msg_count
            msg_count=$(grep -c "^--- MESSAGE ---$" "$mailbox" 2>/dev/null | head -1 || echo "0")
            msg_count=${msg_count:-0}

            if [[ "$msg_count" -gt "$processed_count" ]]; then
                # Process new messages using awk
                # Encode newlines as ␤ (Unicode U+2424) to preserve multi-line messages
                awk -v start=$((processed_count + 1)) '
                    BEGIN { msg_num=0; in_msg=0; in_body=0; from=""; to=""; body="" }
                    /^--- MESSAGE ---$/ {
                        if (in_body && msg_num >= start && to != "") {
                            gsub(/\n$/, "", body)
                            gsub(/\n/, "␤", body)
                            print from "|" to "|" body
                        }
                        msg_num++
                        in_msg=1
                        in_body=0
                        from=""
                        to=""
                        body=""
                        next
                    }
                    in_msg && /^timestamp:/ { next }
                    in_msg && /^from:/ { from=$2; next }
                    in_msg && /^to:/ { to=$2; in_body=1; next }
                    in_body { body = body $0 "\n" }
                    END {
                        if (in_body && msg_num >= start && to != "") {
                            gsub(/\n$/, "", body)
                            gsub(/\n/, "␤", body)
                            print from "|" to "|" body
                        }
                    }
                ' "$mailbox" | while IFS='|' read -r from to body; do
                    if [[ -n "$to" && -n "$body" ]]; then
                        # Route message via tmux, include sender for context
                        # Use -l (literal) to prevent special character interpretation
                        tmux send-keys -t "$SESSION_NAME:$to" -l "[from:$from] "

                        # Decode ␤ back to newlines and send line by line
                        echo "$body" | tr '␤' '\n' | while IFS= read -r line || [[ -n "$line" ]]; do
                            tmux send-keys -t "$SESSION_NAME:$to" -l "$line"
                            tmux send-keys -t "$SESSION_NAME:$to" Enter
                            sleep 0.1
                        done

                        sleep 0.2
                        tmux send-keys -t "$SESSION_NAME:$to" Enter
                        log_step "Routed: $from -> $to"
                    fi
                done

                processed_count=$msg_count
            fi
        fi
        sleep 2
    done
}

#───────────────────────────────────────────────────────────────────────────────
# Feature Discovery
#───────────────────────────────────────────────────────────────────────────────

get_features() {
    local features=()

    if [[ -f "$PROJECT_PATH/.multiclaude/specs/.features" ]]; then
        while IFS= read -r feature; do
            [[ -n "$feature" ]] && [[ ! "$feature" =~ ^# ]] && features+=("$feature")
        done < "$PROJECT_PATH/.multiclaude/specs/.features"
    elif [[ -d "$PROJECT_PATH/.multiclaude/specs/features" ]]; then
        for spec in "$PROJECT_PATH/.multiclaude/specs/features"/*.spec.md; do
            if [[ -f "$spec" ]]; then
                features+=("$(basename "$spec" .spec.md)")
            fi
        done
    fi

    echo "${features[@]}"
}

# Remove a completed feature from the pending list
remove_feature() {
    local feature="$1"
    local features_file="$PROJECT_PATH/.multiclaude/specs/.features"

    if [[ -f "$features_file" ]]; then
        grep -v "^${feature}$" "$features_file" > "${features_file}.tmp" || true
        mv "${features_file}.tmp" "$features_file"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Setup Functions
#───────────────────────────────────────────────────────────────────────────────

setup_worktrees() {
    log_step "Setting up git worktrees..."

    local features=($(get_features))

    if [[ ${#features[@]} -eq 0 ]]; then
        log_error "No features found in .multiclaude/specs/features/*.spec.md or .multiclaude/specs/.features"
        return 1
    fi

    printf "  Features: ${CYAN}${features[*]}${NC}\n"

    # Create a base branch off main for this session
    local base_branch="multiclaude/${PROJECT_NAME}-$(date +%Y%m%d-%H%M%S)"
    git checkout main 2>/dev/null || git checkout -b main 2>/dev/null
    git checkout -b "$base_branch" 2>/dev/null || git checkout "$base_branch" 2>/dev/null
    echo "$base_branch" > "$PROJECT_PATH/.multiclaude/BASE_BRANCH"
    log_success "Created base branch: $base_branch"

    # Create worktrees directory
    mkdir -p .multiclaude/worktrees

    for feature in "${features[@]}"; do
        local branch_name="feature/${feature}"
        local worktree_path="${PROJECT_PATH}/.multiclaude/worktrees/feature-${feature}"

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

        # Setup worktree .multiclaude directory
        mkdir -p "${worktree_path}/.multiclaude"

        # Copy configs
        [[ -f "${PROJECT_PATH}/.mcp.json" ]] && cp "${PROJECT_PATH}/.mcp.json" "${worktree_path}/.mcp.json"
        [[ -f "${PROJECT_PATH}/.multiclaude/settings.json" ]] && cp "${PROJECT_PATH}/.multiclaude/settings.json" "${worktree_path}/.multiclaude/settings.json"
        [[ -f "${PROJECT_PATH}/CLAUDE.md" ]] && cp "${PROJECT_PATH}/CLAUDE.md" "${worktree_path}/CLAUDE.md"

        # Copy feature spec
        if [[ -f "${PROJECT_PATH}/.multiclaude/specs/features/${feature}.spec.md" ]]; then
            cp "${PROJECT_PATH}/.multiclaude/specs/features/${feature}.spec.md" "${worktree_path}/.multiclaude/FEATURE_SPEC.md"
        fi

        # Initialize status log
        echo "$(date -Iseconds) [PENDING] Worktree initialized" > "${worktree_path}/.multiclaude/status.log"

        printf "  ${GREEN}%-15s created${NC}\n" "$feature"
    done

    log_success "Worktrees ready"

    # Enrich any bare specs before workers launch
    log_step "Enriching feature specs..."
    run_spec_phase "$PROJECT_PATH"
    log_success "Specs enriched"
}

install_templates() {
    log_step "Installing agent templates..."

    mkdir -p "$PROJECT_PATH/.multiclaude"
    mkdir -p "$PROJECT_PATH/.multiclaude/qa-reports"
    mkdir -p "$PROJECT_PATH/.multiclaude/fix-tasks"

    # Initialize central mailbox
    if [[ ! -f "$PROJECT_PATH/.multiclaude/mailbox" ]]; then
        touch "$PROJECT_PATH/.multiclaude/mailbox"
        printf "  ${GREEN}✓${NC} mailbox (central message bus)\n"
    fi

    # Supervisor template
    if [[ -f "$SCRIPT_DIR/templates/SUPERVISOR.md" ]]; then
        cp "$SCRIPT_DIR/templates/SUPERVISOR.md" "$PROJECT_PATH/.multiclaude/SUPERVISOR.md"
        printf "  ${GREEN}✓${NC} SUPERVISOR.md\n"
    fi

    # QA template
    if [[ -f "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" ]]; then
        cp "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" "$PROJECT_PATH/.multiclaude/QA_INSTRUCTIONS.md"
        printf "  ${GREEN}✓${NC} QA_INSTRUCTIONS.md\n"
    fi

    # Worker templates
    if [[ -f "$SCRIPT_DIR/templates/WORKER.md" ]]; then
        for worktree in "$PROJECT_PATH"/.multiclaude/worktrees/feature-*; do
            if [[ -d "$worktree" ]]; then
                cp "$SCRIPT_DIR/templates/WORKER.md" "$worktree/.multiclaude/WORKER.md"
            fi
        done
        printf "  ${GREEN}✓${NC} WORKER.md (all worktrees)\n"
    fi

    # Standards template
    if [[ ! -f "$PROJECT_PATH/.multiclaude/specs/STANDARDS.md" ]] && [[ -f "$SCRIPT_DIR/templates/STANDARDS.template.md" ]]; then
        cp "$SCRIPT_DIR/templates/STANDARDS.template.md" "$PROJECT_PATH/.multiclaude/specs/STANDARDS.md"
        printf "  ${GREEN}✓${NC} STANDARDS.md\n"
    fi

    log_success "Templates installed"
}

#───────────────────────────────────────────────────────────────────────────────
# Agent Launching
#───────────────────────────────────────────────────────────────────────────────

launch_agents() {
    # Check if agents are already running (windows already exist)
    local existing_windows
    existing_windows=$(tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -v '^monitor$' || true)

    if [[ -n "$existing_windows" ]]; then
        log_step "Agent windows already exist, skipping launch..."
        printf "  ${DIM}Existing windows: $(echo "$existing_windows" | tr '\n' ' ')${NC}\n"

        # Start mailbox watcher in background if not already running
        if [[ -z "${MAILBOX_PID:-}" ]] || ! kill -0 "$MAILBOX_PID" 2>/dev/null; then
            log_step "Starting mailbox router..."
            watch_mailbox &
            MAILBOX_PID=$!
            printf "  ${GREEN}✓${NC} Mailbox router (PID: %s)\n" "$MAILBOX_PID"
        fi
        return 0
    fi

    log_step "Launching agents..."
    echo ""

    local window_num=1

    #─────────────────────────────────────────────────────────────────────
    # Window 1: Supervisor
    #─────────────────────────────────────────────────────────────────────
    printf "  Creating window $window_num: ${CYAN}supervisor${NC}..."

    tmux new-window -t "$SESSION_NAME" -n "supervisor" \
        "cd '$PROJECT_PATH' && claude --dangerously-skip-permissions"
    # Lock window name to prevent Claude Code from renaming it
    tmux set-option -t "$SESSION_NAME:supervisor" allow-rename off

    local supervisor_prompt="You are the SUPERVISOR AGENT. Read .multiclaude/SUPERVISOR.md for your complete instructions. You coordinate all workers and the QA agent via the central mailbox at .multiclaude/mailbox. Start by reading your instructions, then monitor worker status logs at .multiclaude/worktrees/feature-*/.multiclaude/status.log"

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
    # Lock window name to prevent Claude Code from renaming it
    tmux set-option -t "$SESSION_NAME:qa" allow-rename off

    local qa_prompt="You are the QA AGENT. Read .multiclaude/QA_INSTRUCTIONS.md for your complete instructions. You MUST WAIT for a RUN_QA signal (delivered via tmux from the mailbox router) before running any tests. Start by reading your instructions, then wait for messages."

    sleep 2
    tmux send-keys -t "$SESSION_NAME:qa" "$qa_prompt"
    sleep 0.3
    tmux send-keys -t "$SESSION_NAME:qa" C-m

    printf " ${GREEN}launched${NC}\n"
    ((window_num++))

    #─────────────────────────────────────────────────────────────────────
    # Windows 3+: Workers
    #─────────────────────────────────────────────────────────────────────
    for worktree in "$PROJECT_PATH"/.multiclaude/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')

            printf "  Creating window $window_num: ${CYAN}$feature${NC} (worker)..."

            tmux new-window -t "$SESSION_NAME" -n "$feature" \
                "cd '$worktree' && MAIN_REPO='$PROJECT_PATH' FEATURE='$feature' claude --dangerously-skip-permissions"
            # Lock window name to prevent Claude Code from renaming it
            tmux set-option -t "$SESSION_NAME:$feature" allow-rename off

            local worker_prompt="You are a WORKER AGENT implementing the '$feature' feature. Read .multiclaude/WORKER.md for your complete instructions. Your feature spec is in .multiclaude/FEATURE_SPEC.md. Log your status to .multiclaude/status.log. Use the central mailbox at \$MAIN_REPO/.multiclaude/mailbox for communication. Start by reading your instructions."

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

    # Start mailbox watcher in background
    log_step "Starting mailbox router..."
    watch_mailbox &
    MAILBOX_PID=$!
    printf "  ${GREEN}✓${NC} Mailbox router (PID: %s)\n" "$MAILBOX_PID"
}

#───────────────────────────────────────────────────────────────────────────────
# PR Creation and Cleanup
#───────────────────────────────────────────────────────────────────────────────

generate_pr_body() {
    local qa_report="$PROJECT_PATH/.multiclaude/qa-reports/latest.json"

    # Get features list
    local features=$(cat "$PROJECT_PATH/.multiclaude/specs/.features" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

    # Get QA summary if report exists
    local qa_summary="All standards validated"
    if [[ -f "$qa_report" ]] && command -v jq &>/dev/null; then
        local total=$(jq -r '.summary.total // 0' "$qa_report" 2>/dev/null)
        local passed=$(jq -r '.summary.passed // 0' "$qa_report" 2>/dev/null)
        qa_summary="QA Results: $passed/$total standards passed"
    fi

    cat << EOF
## Summary
Automated PR from multiclaude parallel development workflow.

## Features Implemented
$features

## QA Validation
$qa_summary

All user experience standards have been validated via browser automation testing.

---
Generated by [multiclaude](https://github.com/anthropics/multiclaude)
EOF
}

maybe_create_pr() {
    # Check if auto-pr is enabled
    if [[ "$AUTO_PR" != "true" ]]; then
        return 0
    fi

    # Already attempted?
    if [[ -f "$PROJECT_PATH/.multiclaude/PR_CREATED" ]] || [[ -f "$PROJECT_PATH/.multiclaude/PR_SKIPPED" ]]; then
        return 0
    fi

    log_step "Auto-PR enabled, checking prerequisites..."

    # Check gh CLI available
    if ! command -v gh &>/dev/null; then
        log_warn "GitHub CLI (gh) not found, skipping PR creation"
        touch "$PROJECT_PATH/.multiclaude/PR_SKIPPED"
        return 0
    fi

    # Check gh authenticated
    if ! gh auth status &>/dev/null 2>&1; then
        log_warn "GitHub CLI not authenticated, skipping PR creation"
        touch "$PROJECT_PATH/.multiclaude/PR_SKIPPED"
        return 0
    fi

    # Check remote exists
    if ! git remote get-url origin &>/dev/null 2>&1; then
        log_warn "No git remote 'origin' configured, skipping PR creation"
        touch "$PROJECT_PATH/.multiclaude/PR_SKIPPED"
        return 0
    fi

    cd "$PROJECT_PATH"

    # Read the base branch name
    local base_branch_file="$PROJECT_PATH/.multiclaude/BASE_BRANCH"
    if [[ ! -f "$base_branch_file" ]]; then
        log_warn "No base branch file found, skipping PR creation"
        touch "$PROJECT_PATH/.multiclaude/PR_SKIPPED"
        return 0
    fi

    local pr_branch
    pr_branch=$(cat "$base_branch_file")

    log_step "Pushing base branch: $pr_branch"
    git checkout "$pr_branch" 2>/dev/null

    if ! git push -u origin "$pr_branch" 2>/dev/null; then
        log_error "Failed to push branch"
        touch "$PROJECT_PATH/.multiclaude/PR_SKIPPED"
        return 1
    fi

    # Generate PR body
    local pr_body=$(generate_pr_body)
    local pr_title="[multiclaude] ${PROJECT_NAME} - QA Validated"

    log_step "Creating PR: $pr_branch -> main"

    # Create PR
    local pr_url
    pr_url=$(gh pr create \
        --base "main" \
        --head "$pr_branch" \
        --title "$pr_title" \
        --body "$pr_body" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "PR created: $pr_url"
        echo "$(date -Iseconds) - PR created: $pr_url" > "$PROJECT_PATH/.multiclaude/pr.log"
        touch "$PROJECT_PATH/.multiclaude/PR_CREATED"
        return 0
    else
        log_error "Failed to create PR: $pr_url"
        touch "$PROJECT_PATH/.multiclaude/PR_SKIPPED"
        return 1
    fi
}

cleanup_project() {
    log_step "Cleaning up project..."

    cd "$PROJECT_PATH"

    # Remove worktrees
    if [[ -d "$PROJECT_PATH/.multiclaude/worktrees" ]]; then
        log_step "Removing worktrees..."
        for worktree in "$PROJECT_PATH"/.multiclaude/worktrees/feature-*; do
            if [[ -d "$worktree" ]]; then
                local feature=$(basename "$worktree")
                git worktree remove "$worktree" --force 2>/dev/null || rm -rf "$worktree"
                log_success "Removed $feature"
            fi
        done
        rmdir "$PROJECT_PATH/.multiclaude/worktrees" 2>/dev/null || true
    fi

    # Remove feature branches (but NOT the base branch — it's the PR branch)
    log_step "Removing feature branches..."
    local base_branch=""
    [[ -f "$PROJECT_PATH/.multiclaude/BASE_BRANCH" ]] && base_branch=$(cat "$PROJECT_PATH/.multiclaude/BASE_BRANCH")
    for branch in $(git branch --list 'feature/*' 2>/dev/null); do
        git branch -D "$branch" 2>/dev/null && log_success "Deleted branch $branch"
    done
    if [[ -n "$base_branch" ]]; then
        log_success "Kept base branch: $base_branch (PR branch)"
    fi

    # Archive state files to prevent re-triggering
    local archive_dir="$PROJECT_PATH/.multiclaude-complete-$(date +%Y%m%d-%H%M%S)"
    log_step "Archiving state files to $archive_dir..."
    mkdir -p "$archive_dir"

    if [[ -d "$PROJECT_PATH/.multiclaude" ]]; then
        mv "$PROJECT_PATH/.multiclaude" "$archive_dir/.multiclaude"
        log_success "Archived .multiclaude/"
    fi

    # Stop mailbox watcher
    [[ -n "$MAILBOX_PID" ]] && kill "$MAILBOX_PID" 2>/dev/null

    log_success "Cleanup complete!"

    # Kill the tmux session (this will close everything)
    echo ""
    printf "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║              PROJECT COMPLETE - SESSION CLOSING            ║${NC}\n"
    printf "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""
    printf "State archived to: ${CYAN}$archive_dir${NC}\n"
    echo ""
    echo "Press Enter to close tmux session..."
    read

    tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    exit 0
}

#───────────────────────────────────────────────────────────────────────────────
# Dashboard
#───────────────────────────────────────────────────────────────────────────────

LAST_CTRL_C=0

handle_exit() {
    local now=$(date +%s)
    if [[ $((now - LAST_CTRL_C)) -lt 3 ]]; then
        echo ""
        printf "${RED}Stopping mail daemon...${NC}\n"
        [[ -n "$MAILBOX_PID" ]] && kill "$MAILBOX_PID" 2>/dev/null
        exit 0
    else
        LAST_CTRL_C=$now
        echo ""
        printf "${YELLOW}Mail daemon will stop. Ctrl+C again to quit.${NC}\n"
        printf "${DIM}Agents keep running. Re-attach: tmux attach -t $SESSION_NAME${NC}\n"
        sleep 1
    fi
}

run_dashboard() {
    trap handle_exit INT

    while true; do
        clear
        print_banner

        printf "${DIM}$(date '+%Y-%m-%d %H:%M:%S')${NC}  "
        printf "${DIM}Ctrl+C to quit${NC}\n"
        echo ""

        # Worker status
        printf "${BOLD}Workers:${NC}\n"
        printf "  %-15s %-12s %s\n" "FEATURE" "STATUS" "MESSAGE"
        print_separator

        local total=0
        local complete=0

        for worktree in "$PROJECT_PATH"/.multiclaude/worktrees/feature-*; do
            if [[ -d "$worktree" ]]; then
                ((total++))
                local feature=$(basename "$worktree" | sed 's/feature-//')
                local log="$worktree/.multiclaude/status.log"

                if [[ -f "$log" ]]; then
                    local last=$(grep -E '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' "$log" 2>/dev/null | tail -1)
                    local status=$(echo "$last" | grep -oE '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' | tr -d '[]')
                    local msg=$(echo "$last" | sed 's/.*\] //' | cut -c1-40)

                    if [[ "$status" == "COMPLETE" ]]; then
                        ((complete++))
                        remove_feature "$feature"
                    fi

                    case "$status" in
                        COMPLETE)    color="${GREEN}" ;;
                        IN_PROGRESS) color="${YELLOW}" ;;
                        TESTING)     color="${CYAN}" ;;
                        BLOCKED|FAILED) color="${RED}" ;;
                        *)           color="${NC}"; status="PENDING" ;;
                    esac

                    printf "  %-15s ${color}%-12s${NC} %s\n" "$feature" "$status" "$msg"
                else
                    printf "  %-15s ${DIM}%-12s${NC}\n" "$feature" "NO_LOG"
                fi
            fi
        done

        echo ""

        # Project status
        printf "${BOLD}Status:${NC} "
        if [[ -f "$PROJECT_PATH/.multiclaude/PROJECT_COMPLETE" ]]; then
            printf "${GREEN}PROJECT COMPLETE${NC}\n"

            # Trigger PR creation and cleanup on completion
            echo ""
            maybe_create_pr
            cleanup_project
            # cleanup_project exits, so we won't reach here
        elif [[ -f "$PROJECT_PATH/.multiclaude/QA_COMPLETE" ]]; then
            printf "${GREEN}QA PASSED${NC}\n"
        elif [[ -f "$PROJECT_PATH/.multiclaude/QA_NEEDS_FIXES" ]]; then
            printf "${YELLOW}QA NEEDS FIXES${NC}\n"
        elif [[ -f "$PROJECT_PATH/.multiclaude/ALL_MERGED" ]]; then
            printf "${CYAN}MERGED - QA PENDING${NC}\n"
        else
            printf "${YELLOW}IN PROGRESS${NC} ($complete/$total)\n"
        fi

        echo ""

        # Recent messages
        printf "${BOLD}Messages:${NC}\n"

        if [[ -f "$PROJECT_PATH/.multiclaude/mailbox" ]]; then
            local msg_count
            msg_count=$(grep -c "^--- MESSAGE ---$" "$PROJECT_PATH/.multiclaude/mailbox" 2>/dev/null | head -1 || echo "0")
            msg_count=${msg_count:-0}

            if [[ "$msg_count" -gt 0 ]]; then
                awk '
                    BEGIN { msg_num=0 }
                    /^--- MESSAGE ---$/ { msg_num++; next }
                    /^from:/ { from=$2; next }
                    /^to:/ {
                        to=$2
                        getline body
                        body = substr(body, 1, 45)
                        msgs[msg_num] = sprintf("  %s -> %s: %s", from, to, body)
                    }
                    END {
                        start = (msg_num > 5) ? msg_num - 4 : 1
                        for (i = start; i <= msg_num; i++) {
                            if (msgs[i] != "") print msgs[i]
                        }
                    }
                ' "$PROJECT_PATH/.multiclaude/mailbox"
            else
                printf "  ${DIM}(none)${NC}\n"
            fi
        else
            printf "  ${DIM}(none)${NC}\n"
        fi

        echo ""
        print_separator
        printf "${DIM}Ctrl+b n/p: switch windows | Ctrl+b d: detach${NC}\n"

        sleep 5
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
    echo "  - .multiclaude/specs/features/*.spec.md"
    echo "  - OR .multiclaude/specs/.features (one feature name per line)"
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

# Run dashboard
run_dashboard
