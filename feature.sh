#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# ADD FEATURE TO EXISTING PROJECT
# Adds a new feature to an existing parallelized development project
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared phases library
source "$SCRIPT_DIR/phases.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

validate_feature_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        printf "${RED}Error: Invalid feature name '%s'${NC}\n" "$name"
        echo "Names must start with a letter and contain only letters, numbers, hyphens, underscores."
        exit 1
    fi
    if [[ ${#name} -gt 64 ]]; then
        printf "${RED}Error: Name too long (max 64 chars)${NC}\n"
        exit 1
    fi
}

# Parse arguments
PROJECT_PATH="${1:-.}"
shift || true

FROM_FILE=""
FEATURE_NAME=""
SPEC_ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-file|-f)
            FROM_FILE="$2"
            shift 2
            ;;
        --spec-only)
            SPEC_ONLY="true"
            shift
            ;;
        *)
            [[ -z "$FEATURE_NAME" ]] && FEATURE_NAME="$1"
            shift
            ;;
    esac
done

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_PATH")"

# Non-interactive mode - run in tmux
if [[ -n "$FROM_FILE" ]]; then
    if [[ ! -f "$FROM_FILE" ]]; then
        log_error "File not found: $FROM_FILE"
        exit 1
    fi

    # Convert to absolute path
    FROM_FILE="$(cd "$(dirname "$FROM_FILE")" && pwd)/$(basename "$FROM_FILE")"

    # Derive feature name from filename
    FEATURE_NAME=$(basename "$FROM_FILE" .txt | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

    log_info "Adding feature from brief: $FEATURE_NAME"

    # Bootstrap specs structure if it doesn't exist
    if [[ ! -d "$PROJECT_PATH/.multiclaude/specs" ]]; then
        log_info "Bootstrapping multiclaude structure..."
        mkdir -p "$PROJECT_PATH/.multiclaude/specs/features"
        touch "$PROJECT_PATH/.multiclaude/specs/.features"
    fi

    # Copy brief to project
    mkdir -p "$PROJECT_PATH/.multiclaude"
    cp "$FROM_FILE" "$PROJECT_PATH/.multiclaude/feature-brief-${FEATURE_NAME}.txt"

    # Create tmux session for feature setup
    SETUP_SESSION="claude-${PROJECT_NAME}-add-${FEATURE_NAME}"

    # Create a bare spec from the brief so run_spec_phase can enrich it
    local brief_content
    brief_content="$(cat "$FROM_FILE")"
    cat > "$PROJECT_PATH/.multiclaude/specs/features/${FEATURE_NAME}.spec.md" << EOF
# Feature Specification: ${FEATURE_NAME}

## Meta
- **Feature ID**: FEAT-$(date +%Y%m%d%H%M)
- **Created**: $(date +%Y-%m-%d)

## Overview
${brief_content}

## Acceptance Criteria
- [ ] AC-1: TODO - define acceptance criteria

## Technical Notes
<!-- To be enriched by spec phase -->

## Definition of Done
- [ ] All acceptance criteria met
- [ ] Tests passing
- [ ] Status logged as COMPLETE
EOF

    # Add to features registry
    if ! grep -qx "$FEATURE_NAME" "$PROJECT_PATH/.multiclaude/specs/.features" 2>/dev/null; then
        echo "$FEATURE_NAME" >> "$PROJECT_PATH/.multiclaude/specs/.features"
    fi

    # Marker files for external invokers to poll
    READY_MARKER="$PROJECT_PATH/.multiclaude/FEATURE_READY_${FEATURE_NAME}"
    FAILED_MARKER="$PROJECT_PATH/.multiclaude/FEATURE_FAILED_${FEATURE_NAME}"
    rm -f "$READY_MARKER" "$FAILED_MARKER" 2>/dev/null

    # Development session name (same as multiclaude run uses)
    DEV_SESSION="claude-${PROJECT_NAME}"

    # Run in tmux: create worktree, then start dev session (spec enrichment happens in monitor.sh)
    tmux new-session -d -s "$SETUP_SESSION" -n "add-feature" \
        "cd '$PROJECT_PATH' && \
         '$SCRIPT_DIR/feature.sh' '$PROJECT_PATH' '$FEATURE_NAME' --spec-only && \
         touch '$READY_MARKER' && \
         echo 'Feature ready: $FEATURE_NAME' && \
         echo 'Starting development session...' && \
         tmux new-session -d -s '$DEV_SESSION' -n 'monitor' \
             \"cd '$PROJECT_PATH' && '$SCRIPT_DIR/monitor.sh' '$PROJECT_PATH'\" && \
         echo 'Development session started: $DEV_SESSION' && \
         echo 'Poll for PROJECT_COMPLETE or attach: tmux attach -t $DEV_SESSION' || \
         (touch '$FAILED_MARKER' && echo 'Feature setup failed: $FEATURE_NAME' && exit 1)"

    log_success "Feature setup session: $SETUP_SESSION"
    echo ""
    echo "This will:"
    echo "  1. Create feature spec (Claude)"
    echo "  2. Create git worktree"
    echo "  3. Start development session: $DEV_SESSION"
    echo ""
    echo "Poll:   test -f .multiclaude/PROJECT_COMPLETE && echo 'done'"
    echo "Attach: tmux attach -t $DEV_SESSION"
    exit 0
fi

# Validate inputs for interactive mode
if [[ -z "$FEATURE_NAME" ]]; then
    echo "Usage: multiclaude add <feature-name>"
    echo "       multiclaude add --from-file <brief.txt>"
    exit 1
fi

FEATURE_NAME=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

validate_feature_name "$FEATURE_NAME"

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${BOLD}    ADD FEATURE TO PROJECT${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo "Project: $PROJECT_NAME"
echo "Feature: $FEATURE_NAME"

# Bootstrap specs structure if it doesn't exist
if [[ ! -d "$PROJECT_PATH/.multiclaude/specs" ]]; then
    log_info "Bootstrapping multiclaude structure..."
    mkdir -p "$PROJECT_PATH/.multiclaude/specs/features"
    mkdir -p "$PROJECT_PATH/.multiclaude"
    touch "$PROJECT_PATH/.multiclaude/specs/.features"

    # Create minimal .gitignore additions if .gitignore exists
    if [[ -f "$PROJECT_PATH/.gitignore" ]]; then
        if ! grep -q ".multiclaude/" "$PROJECT_PATH/.gitignore" 2>/dev/null; then
            echo -e "\n# Multiclaude working directory\n.multiclaude/" >> "$PROJECT_PATH/.gitignore"
        fi
    else
        echo "# Multiclaude working directory" > "$PROJECT_PATH/.gitignore"
        echo ".multiclaude/" >> "$PROJECT_PATH/.gitignore"
    fi

    log_success "Created .multiclaude/ structure"
fi

cd "$PROJECT_PATH"

# When --spec-only is set, skip spec creation (it was already created by Claude)
# Just create the worktree
if [[ -z "$SPEC_ONLY" ]]; then
    # Check feature doesn't exist
    if [[ -f "$PROJECT_PATH/.multiclaude/specs/features/${FEATURE_NAME}.spec.md" ]]; then
        log_error "Feature already exists: $FEATURE_NAME"
        exit 1
    fi

    # Prompt for description
    read -p "Feature description: " DESCRIPTION

    # Create spec
    log_info "Creating feature specification..."
    mkdir -p .multiclaude/specs/features

    cat > ".multiclaude/specs/features/${FEATURE_NAME}.spec.md" << EOF
# Feature Specification: ${FEATURE_NAME}

## Meta
- **Feature ID**: FEAT-$(date +%Y%m%d%H%M)
- **Created**: $(date +%Y-%m-%d)

## Overview
${DESCRIPTION}

## Acceptance Criteria
- [ ] AC-1: TODO - define acceptance criteria
- [ ] AC-2: TODO

## Technical Notes
<!-- Worker will determine implementation approach based on existing project patterns -->

## Definition of Done
- [ ] All acceptance criteria met
- [ ] Tests passing
- [ ] Status logged as COMPLETE
EOF

    log_success "Created .multiclaude/specs/features/${FEATURE_NAME}.spec.md"

    # Spec enrichment is handled by monitor.sh before workers launch
fi

# Update registry (deduplicated)
if ! grep -qx "$FEATURE_NAME" ".multiclaude/specs/.features" 2>/dev/null; then
    echo "$FEATURE_NAME" >> ".multiclaude/specs/.features"
fi

# Create worktree
BRANCH_NAME="feature/${FEATURE_NAME}"

# Use external worktree dir if available, otherwise fall back to in-repo
if [[ -f "$PROJECT_PATH/.multiclaude/WORKTREE_DIR" ]]; then
    WORKTREE_BASE=$(cat "$PROJECT_PATH/.multiclaude/WORKTREE_DIR")
else
    WORKTREE_BASE="${PROJECT_PATH}/.multiclaude/worktrees"
fi
WORKTREE_PATH="${WORKTREE_BASE}/feature-${FEATURE_NAME}"

# Create feature branch off the base branch (if it exists), otherwise current HEAD
BASE_BRANCH_REF="HEAD"
if [[ -f "$PROJECT_PATH/.multiclaude/BASE_BRANCH" ]]; then
    BASE_BRANCH_REF=$(cat "$PROJECT_PATH/.multiclaude/BASE_BRANCH")
fi
git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}" || git branch "${BRANCH_NAME}" "${BASE_BRANCH_REF}"

if [[ ! -d "$WORKTREE_PATH" ]]; then
    mkdir -p "$(dirname "$WORKTREE_PATH")"
    git worktree add "${WORKTREE_PATH}" "${BRANCH_NAME}"
    mkdir -p "${WORKTREE_PATH}/.multiclaude"
    [[ -f ".mcp.json" ]] && cp ".mcp.json" "${WORKTREE_PATH}/.mcp.json"
    [[ -f ".multiclaude/settings.json" ]] && cp ".multiclaude/settings.json" "${WORKTREE_PATH}/.multiclaude/settings.json"
    cp ".multiclaude/specs/features/${FEATURE_NAME}.spec.md" "${WORKTREE_PATH}/.multiclaude/FEATURE_SPEC.md"
    [[ -f "$SCRIPT_DIR/templates/WORKER.md" ]] && cp "$SCRIPT_DIR/templates/WORKER.md" "${WORKTREE_PATH}/.multiclaude/WORKER.md"
    echo "$(date -Iseconds) [PENDING] Worktree initialized" > "${WORKTREE_PATH}/.multiclaude/status.log"
    echo "# Worker Inbox" > "${WORKTREE_PATH}/.multiclaude/inbox.md"
    log_success "Created worktree: $WORKTREE_PATH"
fi

# Launch worker if session running (skip if --spec-only as we're being called from a setup tmux session)
if [[ -z "$SPEC_ONLY" ]]; then
    SESSION_NAME="claude-${PROJECT_NAME}"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log_info "Adding worker to running session..."

        tmux new-window -t "$SESSION_NAME" -n "$FEATURE_NAME" \
            "cd '$WORKTREE_PATH' && MAIN_REPO='$PROJECT_PATH' FEATURE='$FEATURE_NAME' claude --dangerously-skip-permissions"

        sleep 2
        tmux send-keys -t "$SESSION_NAME:$FEATURE_NAME" \
            "You are a WORKER AGENT for '$FEATURE_NAME'. Read .multiclaude/WORKER.md for instructions." C-m

        # Notify supervisor about the new feature via mailbox
        cat >> "$PROJECT_PATH/.multiclaude/mailbox" << MSGEOF
--- MESSAGE ---
timestamp: $(date -Iseconds)
from: monitor
to: supervisor
NEW_FEATURE: $FEATURE_NAME added to the project.
Spec at .multiclaude/specs/features/${FEATURE_NAME}.spec.md
Worker launched in window: $FEATURE_NAME
MSGEOF

        log_success "Worker launched: $SESSION_NAME:$FEATURE_NAME"
    else
        echo -e "${GREEN}Feature added: ${FEATURE_NAME}${NC}"
        echo "Start: multiclaude run ."
    fi
else
    log_success "Worktree created for feature: $FEATURE_NAME"
fi
