#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# ADD FEATURE TO EXISTING PROJECT
# Adds a new feature to an existing parallelized development project
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:-.}"
FEATURE_NAME="$2"

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

print_usage() {
    echo "Usage: $0 <project-path> <feature-name> [options]"
    echo ""
    echo "Options:"
    echo "  --description \"desc\"   Feature description"
    echo "  --deps \"feat1,feat2\"   Dependent features"
    echo "  --no-worktree          Skip worktree creation"
    echo "  --launch               Launch Claude worker after setup"
}

DESCRIPTION=""
DEPENDENCIES=""
NO_WORKTREE=false
LAUNCH=false

shift 2 2>/dev/null || true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --description) DESCRIPTION="$2"; shift 2 ;;
        --deps) DEPENDENCIES="$2"; shift 2 ;;
        --no-worktree) NO_WORKTREE=true; shift ;;
        --launch) LAUNCH=true; shift ;;
        --help|-h) print_usage; exit 0 ;;
        *) shift ;;
    esac
done

if [[ -z "$PROJECT_PATH" ]] || [[ -z "$FEATURE_NAME" ]]; then
    print_usage
    exit 1
fi

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_PATH")"
FEATURE_NAME=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${BOLD}    ADD FEATURE TO PROJECT${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo "Project: $PROJECT_NAME"
echo "Feature: $FEATURE_NAME"

if [[ ! -d "$PROJECT_PATH/specs" ]]; then
    log_error "Not a valid project: $PROJECT_PATH"
    exit 1
fi

if [[ -f "$PROJECT_PATH/specs/features/${FEATURE_NAME}.spec.md" ]]; then
    log_error "Feature already exists: $FEATURE_NAME"
    exit 1
fi

cd "$PROJECT_PATH"

[[ -z "$DESCRIPTION" ]] && read -p "Feature description: " DESCRIPTION

Feature="$(tr '[:lower:]' '[:upper:]' <<< ${FEATURE_NAME:0:1})${FEATURE_NAME:1}"

log_info "Creating feature specification..."
mkdir -p specs/features

cat > "specs/features/${FEATURE_NAME}.spec.md" << EOF
# Feature Specification: ${Feature}

## Meta
- **Feature ID**: FEAT-$(date +%Y%m%d%H%M)
- **Module**: ${FEATURE_NAME}
- **Dependencies**: ${DEPENDENCIES:-None}
- **Created**: $(date +%Y-%m-%d)

## Overview
${DESCRIPTION}

## Acceptance Criteria
- [ ] AC-1: TODO
- [ ] AC-2: TODO

## Technical Requirements
| File Path | Action |
|-----------|--------|
| src/${FEATURE_NAME}/index.ts | Create |
| src/${FEATURE_NAME}/${FEATURE_NAME}.service.ts | Create |
| src/${FEATURE_NAME}/${FEATURE_NAME}.types.ts | Create |

## Definition of Done
- [ ] All acceptance criteria met
- [ ] Unit tests passing (>80% coverage)
- [ ] Status logged as COMPLETE
EOF

log_success "Created specs/features/${FEATURE_NAME}.spec.md"

mkdir -p "src/${FEATURE_NAME}/__tests__"

cat > "src/${FEATURE_NAME}/index.ts" << EOF
export * from './${FEATURE_NAME}.service';
export * from './${FEATURE_NAME}.types';
EOF

cat > "src/${FEATURE_NAME}/${FEATURE_NAME}.types.ts" << EOF
export interface ${Feature}Config {}
export interface ${Feature}Entity { id: string; createdAt: Date; updatedAt: Date; }
EOF

cat > "src/${FEATURE_NAME}/${FEATURE_NAME}.service.ts" << EOF
import { ${Feature}Config } from './${FEATURE_NAME}.types';
export class ${Feature}Service {
  constructor(private config: ${Feature}Config) {}
  async initialize(): Promise<void> {}
}
EOF

log_success "Created src/${FEATURE_NAME}/"

echo "$FEATURE_NAME" >> "specs/.features" 2>/dev/null || echo "$FEATURE_NAME" > "specs/.features"

if [[ "$NO_WORKTREE" != true ]]; then
    BRANCH_NAME="feature/${FEATURE_NAME}"
    WORKTREE_PATH="${PROJECT_PATH}/worktrees/feature-${FEATURE_NAME}"
    
    git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}" || git branch "${BRANCH_NAME}"
    
    if [[ ! -d "$WORKTREE_PATH" ]]; then
        git worktree add "${WORKTREE_PATH}" "${BRANCH_NAME}"
        mkdir -p "${WORKTREE_PATH}/.claude"
        [[ -f ".mcp.json" ]] && cp ".mcp.json" "${WORKTREE_PATH}/.mcp.json"
        [[ -f ".claude/settings.json" ]] && cp ".claude/settings.json" "${WORKTREE_PATH}/.claude/settings.json"
        cp "specs/features/${FEATURE_NAME}.spec.md" "${WORKTREE_PATH}/.claude/FEATURE_SPEC.md"
        [[ -f "$SCRIPT_DIR/templates/WORKER.md" ]] && cp "$SCRIPT_DIR/templates/WORKER.md" "${WORKTREE_PATH}/.claude/WORKER.md"
        echo "$(date -Iseconds) [PENDING] Worktree initialized" > "${WORKTREE_PATH}/.claude/status.log"
        echo "# Worker Inbox" > "${WORKTREE_PATH}/.claude/inbox.md"
        log_success "Created worktree: $WORKTREE_PATH"
    fi
fi

git add -A && git commit -m "feat: add ${FEATURE_NAME} feature scaffold" 2>/dev/null || true

echo -e "${GREEN}Feature added: ${FEATURE_NAME}${NC}"
echo "Next: ./scripts/launch-claude.sh ${FEATURE_NAME}"
