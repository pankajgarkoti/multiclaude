#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# MULTICLAUDE DEVELOPMENT LOOP
#
# Creates a tmux session where Window 0 is the control center.
# All setup and agent launching happens visibly from Window 0.
#
# Session Structure:
#   Window 0: Monitor (control center - you are here)
#   Window 1: Supervisor Agent
#   Window 2: QA Agent
#   Window 3+: Worker Agents
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

# Check if already in tmux
if [[ -n "$TMUX" ]]; then
    current_session=$(tmux display-message -p '#S')
    if [[ "$current_session" == "$SESSION_NAME" ]]; then
        # We're inside the monitor pane - run the orchestration
        exec "$SCRIPT_DIR/monitor.sh" "$PROJECT_PATH"
    else
        # We're in a different tmux session
        printf "${YELLOW}Already inside tmux session '$current_session'${NC}\n"
        echo ""

        # Check if target session exists
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "Session '$SESSION_NAME' already exists."
            read -p "Switch to it? (Y/n): " switch
            if [[ ! "$switch" =~ ^[Nn] ]]; then
                exec tmux switch-client -t "$SESSION_NAME"
            fi
            exit 0
        else
            echo "Create session '$SESSION_NAME' and switch to it?"
            read -p "(Y/n): " confirm
            if [[ "$confirm" =~ ^[Nn] ]]; then
                exit 0
            fi

            # Create session in background and switch
            tmux new-session -d -s "$SESSION_NAME" -n "monitor" \
                "cd '$PROJECT_PATH' && '$SCRIPT_DIR/monitor.sh' '$PROJECT_PATH'"
            exec tmux switch-client -t "$SESSION_NAME"
        fi
    fi
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

printf "${CYAN}"
cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║         MULTICLAUDE DEVELOPMENT LOOP                              ║
    ║         Launching Control Center...                               ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
printf "${NC}\n"

echo "Project: $PROJECT_NAME"
echo "Path:    $PROJECT_PATH"
echo ""

# Check dependencies
for cmd in tmux claude git; do
    if ! command -v $cmd &>/dev/null; then
        printf "${RED}Error: $cmd is required but not installed${NC}\n"
        exit 1
    fi
done

# Check if tmux session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    printf "${YELLOW}Session '$SESSION_NAME' already exists.${NC}\n"
    echo ""
    echo "Options:"
    echo "  1) Attach to existing session"
    echo "  2) Kill and restart"
    echo "  3) Cancel"
    echo ""
    read -p "Choice [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1)
            exec tmux attach -t "$SESSION_NAME"
            ;;
        2)
            tmux kill-session -t "$SESSION_NAME"
            printf "${GREEN}Killed existing session${NC}\n"
            ;;
        *)
            echo "Cancelled."
            exit 0
            ;;
    esac
fi

# Create tmux session with window 0 as the monitor/control center
printf "${BOLD}Creating tmux session...${NC}\n"

tmux new-session -d -s "$SESSION_NAME" -n "monitor" \
    "cd '$PROJECT_PATH' && '$SCRIPT_DIR/loop.sh' '$PROJECT_PATH'"

# Attach to the session
printf "${GREEN}Attaching to session...${NC}\n"
exec tmux attach -t "$SESSION_NAME"
