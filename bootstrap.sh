#!/bin/bash
set -e

#═══════════════════════════════════════════════════════════════════════════════
# PARALLEL DEVELOPMENT WORKFLOW BOOTSTRAPPER
# Creates a complete project structure for parallelized Claude Code development
#═══════════════════════════════════════════════════════════════════════════════

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#───────────────────────────────────────────────────────────────────────────────
# Helper Functions
#───────────────────────────────────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║     PARALLEL DEVELOPMENT WORKFLOW BOOTSTRAPPER                    ║
    ║     Multi-Claude Feature Development System                       ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        read -p "$(echo -e "${BOLD}$prompt${NC} [$default]: ")" result
        echo "${result:-$default}"
    else
        read -p "$(echo -e "${BOLD}$prompt${NC}: ")" result
        echo "$result"
    fi
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local result

    read -p "$(echo -e "${BOLD}$prompt${NC} [${default}]: ")" result
    result="${result:-$default}"
    [[ "$result" =~ ^[Yy] ]]
}

#───────────────────────────────────────────────────────────────────────────────
# Project Structure Creation
#───────────────────────────────────────────────────────────────────────────────

create_directory_structure() {
    local project_dir="$1"

    log_info "Creating directory structure..."

    mkdir -p "$project_dir"/{.claude,specs/features,scripts,src,docs}

    log_success "Directory structure created"
}

init_git_repo() {
    local project_dir="$1"

    log_info "Initializing git repository..."

    cd "$project_dir"

    if [[ ! -d .git ]]; then
        git init
        git checkout -b main
    fi

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Worktrees (managed separately)
worktrees/

# Environment
.env
.env.local
.env.*.local

# Dependencies
node_modules/
vendor/
venv/
__pycache__/

# Build outputs
dist/
build/
*.o
*.pyc

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
*.log
!specs/**/*.log

# Claude working files (keep status logs)
.claude/cache/
.claude/tmp/
EOF

    log_success "Git repository initialized"
}

#───────────────────────────────────────────────────────────────────────────────
# MCP Configuration & Tool Setup
#───────────────────────────────────────────────────────────────────────────────

create_mcp_config() {
    local project_dir="$1"

    log_info "Creating MCP and tool configurations..."

    # ─────────────────────────────────────────────────────────────────────────
    # Create Claude Code settings.json (project-level)
    # This is the main configuration file Claude Code reads
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/.claude/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(node:*)",
      "Bash(git:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(mkdir:*)",
      "Bash(touch:*)",
      "Read",
      "Write",
      "Edit"
    ],
    "deny": []
  },
  "env": {
    "CLAUDE_STATUS_LOG": ".claude/status.log",
    "CLAUDE_IMPL_LOG": ".claude/implementation.log"
  }
}
EOF

    # ─────────────────────────────────────────────────────────────────────────
    # Create .mcp.json for MCP server configuration
    # Claude Code reads this for MCP server definitions
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/.mcp.json" << 'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": {},
      "disabled": false
    },
    "browseruse": {
      "command": "npx",
      "args": ["-y", "@anthropic/browseruse-mcp@latest"],
      "env": {
        "BROWSERUSE_HEADLESS": "true"
      },
      "disabled": false
    }
  }
}
EOF

    # ─────────────────────────────────────────────────────────────────────────
    # Create CLAUDE.md - instructions file Claude Code reads automatically
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/CLAUDE.md" << 'EOF'
# Claude Code Project Instructions

## MCP Servers Available

You have access to the following MCP servers:

### context7
- **Purpose**: Library documentation and code context lookup
- **Usage**: Use to fetch documentation for any library/framework
- **Example**: Get docs for React, Express, Prisma, etc.

### browseruse
- **Purpose**: Web browser automation and research
- **Usage**: Navigate websites, research documentation, verify APIs
- **Example**: Look up API documentation, check package versions

## Workflow Instructions

When working on a feature in this project:

1. **Always read** `.claude/FEATURE_SPEC.md` first if it exists
2. **Log status** to `.claude/status.log` using format:
   ```
   $(date -Iseconds) [STATUS] Message
   ```
   Status codes: PENDING, IN_PROGRESS, BLOCKED, TESTING, COMPLETE, FAILED

3. **Log implementation details** to `.claude/implementation.log`

4. **Use context7** to look up documentation for libraries before using them

5. **Use browseruse** for web research when needed

## Code Standards

- Follow existing code patterns in the project
- Write tests for all new functionality
- Do not modify files outside your feature boundary
- Update status log at each milestone
EOF

    # ─────────────────────────────────────────────────────────────────────────
    # Create setup script for MCP dependencies
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/scripts/setup-mcp.sh" << 'SCRIPT_EOF'
#!/bin/bash
set -e

echo "Setting up MCP servers and dependencies..."

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required but not installed."
    echo "Please install Node.js from https://nodejs.org/"
    exit 1
fi

# Check for npx
if ! command -v npx &> /dev/null; then
    echo "Error: npx is required but not installed."
    echo "Please install npm/npx with Node.js"
    exit 1
fi

echo "Pre-caching MCP server packages..."

# Pre-install MCP packages to avoid delays during Claude sessions
npx -y @upstash/context7-mcp@latest --help 2>/dev/null || true
npx -y @anthropic/browseruse-mcp@latest --help 2>/dev/null || true

echo ""
echo "MCP servers ready!"
echo ""
echo "Available servers:"
echo "  - context7: Documentation and code context lookup"
echo "  - browseruse: Web browser automation"
echo ""

# Check for Claude Code
if command -v claude &> /dev/null; then
    echo "Claude Code CLI: $(claude --version 2>/dev/null || echo 'installed')"
else
    echo "Warning: Claude Code CLI not found in PATH"
    echo "Install from: https://claude.ai/code"
fi
SCRIPT_EOF

    chmod +x "$project_dir/scripts/setup-mcp.sh"

    # ─────────────────────────────────────────────────────────────────────────
    # Create environment template
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/.env.example" << 'EOF'
# MCP Server Configuration
# Copy this file to .env and fill in any required values

# Context7 MCP (if API key required)
# CONTEXT7_API_KEY=

# Browseruse MCP
BROWSERUSE_HEADLESS=true
# BROWSERUSE_PROXY=

# Project Settings
NODE_ENV=development
EOF

    log_success "MCP and tool configurations created"
}

#───────────────────────────────────────────────────────────────────────────────
# Project Specification Template
#───────────────────────────────────────────────────────────────────────────────

create_project_spec() {
    local project_dir="$1"
    local project_name="$2"
    local project_description="$3"

    log_info "Creating project specification template..."

    cat > "$project_dir/specs/PROJECT_SPEC.md" << EOF
# Project Specification: ${project_name}

## 1. Executive Summary

### Project Purpose
${project_description}

### Target Users
<!-- Define your target user personas -->
- User Type A: Description
- User Type B: Description

### Key Value Proposition
<!-- What makes this project valuable? -->

---

## 2. System Architecture

### High-Level Architecture
\`\`\`
┌─────────────────────────────────────────────────────────┐
│                    [Your Architecture]                   │
│                                                         │
│   ┌─────────┐     ┌─────────┐     ┌─────────┐          │
│   │ Layer 1 │────▶│ Layer 2 │────▶│ Layer 3 │          │
│   └─────────┘     └─────────┘     └─────────┘          │
│                                                         │
└─────────────────────────────────────────────────────────┘
\`\`\`

### Technology Stack
| Layer | Technology | Rationale |
|-------|------------|-----------|
| Frontend | | |
| Backend | | |
| Database | | |
| Infrastructure | | |

### Infrastructure Requirements
- Compute:
- Storage:
- Network:

---

## 3. Domain Model

### Core Entities
<!-- Define your main data entities and their relationships -->

\`\`\`
Entity A ──────┬────── Entity B
               │
               └────── Entity C
\`\`\`

### Data Flow
<!-- How does data move through the system? -->

### State Management
<!-- How is application state managed? -->

---

## 4. Feature Modules

<!--
IMPORTANT: Each feature module below should map to a separate feature spec
in specs/features/. These define the boundaries for parallel development.
-->

### 4.1 Feature Module: [Name]
- **Responsibility**: What this module owns
- **Public Interface**: Exported functions/classes
- **Dependencies**: What it needs from other modules
- **Data Ownership**: What data this module manages

### 4.2 Feature Module: [Name]
- **Responsibility**:
- **Public Interface**:
- **Dependencies**:
- **Data Ownership**:

<!-- Add more feature modules as needed -->

---

## 5. Cross-Cutting Concerns

### Authentication & Authorization
<!-- How are users authenticated? What authorization model? -->

### Logging & Monitoring
<!-- What gets logged? How is the system monitored? -->

### Error Handling
<!-- Standard error handling patterns -->

### Configuration Management
<!-- How is configuration handled across environments? -->

---

## 6. Integration Points

### External APIs
| API | Purpose | Auth Method |
|-----|---------|-------------|
| | | |

### Internal Module Communication
<!-- How do modules communicate? REST, events, direct calls? -->

### Event/Message Contracts
<!-- Define any async communication contracts -->

---

## 7. Non-Functional Requirements

### Performance
- Response time targets:
- Throughput targets:
- Resource limits:

### Security
- Data encryption:
- Input validation:
- Access control:

### Scalability
- Horizontal scaling approach:
- Bottleneck mitigation:

---

## 8. Development Guidelines

### Code Style
<!-- Link to or define code style guide -->

### Testing Requirements
- Unit test coverage target: 80%+
- Integration test requirements:
- E2E test requirements:

### Documentation Standards
- Code comments:
- API documentation:
- Architecture decision records:

---

## 9. Feature Breakdown for Parallel Development

| Feature ID | Name | Dependencies | Complexity | Spec File |
|------------|------|--------------|------------|-----------|
| FEAT-001 | | None | Medium | features/xxx.spec.md |
| FEAT-002 | | FEAT-001 | High | features/yyy.spec.md |

---

*Specification Version: 1.0*
*Created: $(date +%Y-%m-%d)*
*Last Updated: $(date +%Y-%m-%d)*
EOF

    log_success "Project specification template created"
}

#───────────────────────────────────────────────────────────────────────────────
# Feature Specification Template
#───────────────────────────────────────────────────────────────────────────────

create_feature_spec() {
    local project_dir="$1"
    local feature_id="$2"
    local feature_name="$3"
    local feature_description="$4"

    local safe_name=$(echo "$feature_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    local spec_file="$project_dir/specs/features/${safe_name}.spec.md"

    log_info "Creating feature spec: $feature_name..."

    cat > "$spec_file" << EOF
# Feature Specification: ${feature_name}

## Meta
- **Feature ID**: ${feature_id}
- **Module**: ${safe_name}
- **Dependencies**: <!-- List dependent features, e.g., FEAT-001 -->
- **Estimated Complexity**: Medium <!-- Low/Medium/High -->
- **Created**: $(date +%Y-%m-%d)

---

## 1. Overview

${feature_description}

---

## 2. Acceptance Criteria

- [ ] **AC-1**: <!-- First acceptance criterion -->
- [ ] **AC-2**: <!-- Second acceptance criterion -->
- [ ] **AC-3**: <!-- Third acceptance criterion -->
- [ ] **AC-4**: <!-- Additional criteria as needed -->

---

## 3. Technical Requirements

### 3.1 Files to Create/Modify

| File Path | Action | Description |
|-----------|--------|-------------|
| \`src/${safe_name}/index.ts\` | Create | Module entry point |
| \`src/${safe_name}/${safe_name}.service.ts\` | Create | Core service logic |
| \`src/${safe_name}/${safe_name}.types.ts\` | Create | Type definitions |
| \`src/${safe_name}/__tests__/\` | Create | Test directory |

### 3.2 Interface Contracts

\`\`\`typescript
// Define the public interface this feature must implement
// Other features will depend on this contract

export interface I${feature_name}Service {
  // Define methods
}

export interface ${feature_name}Config {
  // Define configuration options
}
\`\`\`

### 3.3 Data Models

\`\`\`typescript
// Define data structures this feature owns

export interface ${feature_name}Entity {
  id: string;
  // Add fields
  createdAt: Date;
  updatedAt: Date;
}
\`\`\`

### 3.4 External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| | | |

---

## 4. Implementation Notes

### Edge Cases to Handle
- <!-- Edge case 1 -->
- <!-- Edge case 2 -->

### Performance Considerations
- <!-- Performance note 1 -->

### Security Considerations
- <!-- Security note 1 -->

---

## 5. Testing Requirements

### Unit Tests
- [ ] Test case 1: Description
- [ ] Test case 2: Description
- [ ] Test case 3: Description

### Integration Tests
- [ ] Integration test 1: Description

### Test Data Requirements
\`\`\`typescript
// Define test fixtures needed
const testFixtures = {
  // ...
};
\`\`\`

---

## 6. Definition of Done

- [ ] All acceptance criteria met and verified
- [ ] Unit tests written and passing (>80% coverage)
- [ ] Integration tests written and passing
- [ ] No linting or type errors
- [ ] Code reviewed (via Ralph suggestions)
- [ ] Documentation updated
- [ ] Status logged as COMPLETE in .claude/status.log

---

## 7. Claude Instance Instructions

When implementing this feature:

1. **Start**: Update status.log with \`IN_PROGRESS Starting ${feature_name} implementation\`
2. **Read**: Review this spec and the base implementation in src/
3. **Plan**: Use Ralph plugin to plan the implementation approach
4. **Implement**: Write code following existing patterns
5. **Test**: Write and run tests, fix any failures
6. **Document**: Update any relevant documentation
7. **Complete**: Update status.log with \`COMPLETE All acceptance criteria met\`

### MCP Usage
- Use **context7** to understand existing codebase patterns
- Use **browseruse** to research external library documentation

### Boundaries
- Only modify files within \`src/${safe_name}/\`
- Do not modify shared interfaces without logging BLOCKED status
- Respect the interface contracts defined above

---

*Feature Spec Version: 1.0*
EOF

    log_success "Feature spec created: $spec_file"
    echo "$safe_name"
}

#───────────────────────────────────────────────────────────────────────────────
# Scripts Generation
#───────────────────────────────────────────────────────────────────────────────

create_scripts() {
    local project_dir="$1"
    shift
    local features=("$@")

    log_info "Creating workflow scripts..."

    # ─────────────────────────────────────────────────────────────────────────
    # setup-worktrees.sh
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/scripts/setup-worktrees.sh" << 'SCRIPT_EOF'
#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Feature list - edit this array to match your features
FEATURES=(FEATURE_LIST_PLACEHOLDER)

echo "Setting up worktrees for features: ${FEATURES[*]}"

# Ensure we're on main and up to date
git checkout main 2>/dev/null || git checkout -b main

# Create worktrees directory
mkdir -p worktrees

for feature in "${FEATURES[@]}"; do
    BRANCH_NAME="feature/${feature}"
    WORKTREE_PATH="${PROJECT_ROOT}/worktrees/feature-${feature}"

    echo "─────────────────────────────────────────"
    echo "Setting up: $feature"

    # Skip if worktree already exists
    if [[ -d "$WORKTREE_PATH" ]]; then
        echo "  Worktree already exists, skipping..."
        continue
    fi

    # Create branch if it doesn't exist
    if ! git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
        git branch "${BRANCH_NAME}"
        echo "  Created branch: ${BRANCH_NAME}"
    fi

    # Create worktree
    git worktree add "${WORKTREE_PATH}" "${BRANCH_NAME}"
    echo "  Created worktree: ${WORKTREE_PATH}"

    # Create .claude directory
    mkdir -p "${WORKTREE_PATH}/.claude"

    # ─────────────────────────────────────────────────────────────────────
    # Copy MCP configuration (.mcp.json) to worktree root
    # This is what Claude Code reads for MCP server definitions
    # ─────────────────────────────────────────────────────────────────────
    if [[ -f "${PROJECT_ROOT}/.mcp.json" ]]; then
        cp "${PROJECT_ROOT}/.mcp.json" "${WORKTREE_PATH}/.mcp.json"
        echo "  Copied MCP server configuration"
    fi

    # ─────────────────────────────────────────────────────────────────────
    # Copy Claude settings to worktree
    # ─────────────────────────────────────────────────────────────────────
    if [[ -f "${PROJECT_ROOT}/.claude/settings.json" ]]; then
        cp "${PROJECT_ROOT}/.claude/settings.json" "${WORKTREE_PATH}/.claude/settings.json"
        echo "  Copied Claude settings"
    fi

    # ─────────────────────────────────────────────────────────────────────
    # Create worktree-specific CLAUDE.md with feature instructions
    # ─────────────────────────────────────────────────────────────────────
    cat > "${WORKTREE_PATH}/CLAUDE.md" << CLAUDE_EOF
# Claude Code Instructions - Feature: ${feature}

## Your Assignment
You are implementing the **${feature}** feature in a parallelized development workflow.

## MCP Servers Available

### context7
- **Command**: Use to look up library/framework documentation
- **When to use**: Before using any external library, fetch its docs first
- **Example queries**: "react hooks", "express middleware", "prisma schema"

### browseruse
- **Command**: Web browser for research and verification
- **When to use**: API documentation, troubleshooting, version checking
- **Headless mode**: Enabled by default

## Required Workflow

### 1. Status Logging (REQUIRED)
Write ALL progress updates to \`.claude/status.log\`:
\`\`\`
\$(date -Iseconds) [STATUS] Your message here
\`\`\`

**Status Codes:**
- \`PENDING\` - Not started
- \`IN_PROGRESS\` - Actively working
- \`BLOCKED\` - Cannot proceed (explain why!)
- \`TESTING\` - Running tests
- \`COMPLETE\` - All acceptance criteria met
- \`FAILED\` - Unrecoverable error

### 2. Implementation Logging
Track all changes in \`.claude/implementation.log\`:
- Files created/modified
- Dependencies added
- Test coverage

### 3. Read Your Spec First
**IMPORTANT**: Read \`.claude/FEATURE_SPEC.md\` before starting any work!

## Feature Boundaries
- **Your directory**: \`src/${feature}/\`
- **Do NOT modify**: Files outside your feature directory
- **Shared interfaces**: If you need to change shared types, log BLOCKED status

## Code Standards
- Follow existing patterns in the codebase
- Write tests for all new functionality (target: 80% coverage)
- No linting errors
- Use TypeScript strict mode

## Starting Checklist
1. [ ] Read .claude/FEATURE_SPEC.md
2. [ ] Log: IN_PROGRESS Starting implementation
3. [ ] Review existing code in src/${feature}/
4. [ ] Use context7 to fetch relevant library docs
5. [ ] Implement according to spec
6. [ ] Write tests
7. [ ] Log: COMPLETE when done
CLAUDE_EOF
    echo "  Created CLAUDE.md with feature instructions"

    # ─────────────────────────────────────────────────────────────────────
    # Initialize status log
    # ─────────────────────────────────────────────────────────────────────
    cat > "${WORKTREE_PATH}/.claude/status.log" << STATUS_EOF
# Claude Status Log - Feature: ${feature}
# Format: [TIMESTAMP] [STATUS] [MESSAGE]
# Status: PENDING | IN_PROGRESS | BLOCKED | TESTING | COMPLETE | FAILED

$(date -Iseconds) [PENDING] Worktree initialized, awaiting Claude instance
STATUS_EOF

    # ─────────────────────────────────────────────────────────────────────
    # Initialize implementation log
    # ─────────────────────────────────────────────────────────────────────
    cat > "${WORKTREE_PATH}/.claude/implementation.log" << IMPL_EOF
# Implementation Log - Feature: ${feature}
# Auto-updated by Claude instance

## Files Modified
(none yet)

## Dependencies Added
(none yet)

## Test Coverage
- Unit: 0%
- Integration: 0%

## Notes
(none yet)
IMPL_EOF

    # ─────────────────────────────────────────────────────────────────────
    # Copy feature spec
    # ─────────────────────────────────────────────────────────────────────
    if [[ -f "${PROJECT_ROOT}/specs/features/${feature}.spec.md" ]]; then
        cp "${PROJECT_ROOT}/specs/features/${feature}.spec.md" "${WORKTREE_PATH}/.claude/FEATURE_SPEC.md"
        echo "  Copied feature spec"
    else
        echo "  WARNING: No feature spec found at specs/features/${feature}.spec.md"
    fi

    # ─────────────────────────────────────────────────────────────────────
    # Copy environment template
    # ─────────────────────────────────────────────────────────────────────
    if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
        cp "${PROJECT_ROOT}/.env.example" "${WORKTREE_PATH}/.env.example"
    fi

    echo "  Setup complete!"
done

echo ""
echo "═══════════════════════════════════════════"
echo "All worktrees created successfully!"
echo ""
echo "Each worktree has:"
echo "  - .mcp.json (MCP server configuration)"
echo "  - .claude/settings.json (Claude permissions)"
echo "  - CLAUDE.md (Feature-specific instructions)"
echo "  - .claude/FEATURE_SPEC.md (Implementation spec)"
echo "  - .claude/status.log (Progress tracking)"
echo ""
echo "Next steps:"
echo "  1. Review feature specs in specs/features/"
echo "  2. Run: ./scripts/launch-claude.sh <feature-name>"
echo "  3. Monitor: ./scripts/monitor.sh"
echo "═══════════════════════════════════════════"
SCRIPT_EOF

    # Replace placeholder with actual features
    local features_str=$(printf '"%s" ' "${features[@]}")
    sed -i.bak "s/FEATURE_LIST_PLACEHOLDER/${features_str}/" "$project_dir/scripts/setup-worktrees.sh"
    rm -f "$project_dir/scripts/setup-worktrees.sh.bak"

    # ─────────────────────────────────────────────────────────────────────────
    # launch-claude.sh
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/scripts/launch-claude.sh" << 'SCRIPT_EOF'
#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_usage() {
    echo -e "${BOLD}Usage:${NC} $0 <feature-name> [options]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --all           Launch Claude for all features"
    echo "  --tmux          Launch in tmux sessions"
    echo "  --background    Launch in background"
    echo "  --check-mcp     Verify MCP servers are working"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 auth                    # Launch Claude for auth feature"
    echo "  $0 --all --tmux            # Launch all features in tmux"
    echo "  $0 api --background        # Launch api feature in background"
}

check_mcp_servers() {
    echo -e "${CYAN}Checking MCP server availability...${NC}"
    echo ""

    # Check context7
    echo -n "  context7: "
    if npx -y @upstash/context7-mcp@latest --help &>/dev/null; then
        echo -e "${GREEN}available${NC}"
    else
        echo -e "${YELLOW}installing on first use${NC}"
    fi

    # Check browseruse
    echo -n "  browseruse: "
    if npx -y @anthropic/browseruse-mcp@latest --help &>/dev/null; then
        echo -e "${GREEN}available${NC}"
    else
        echo -e "${YELLOW}installing on first use${NC}"
    fi

    echo ""
}

verify_worktree_config() {
    local worktree_path="$1"
    local missing=()

    [[ ! -f "${worktree_path}/.mcp.json" ]] && missing+=(".mcp.json")
    [[ ! -f "${worktree_path}/CLAUDE.md" ]] && missing+=("CLAUDE.md")
    [[ ! -f "${worktree_path}/.claude/FEATURE_SPEC.md" ]] && missing+=(".claude/FEATURE_SPEC.md")
    [[ ! -f "${worktree_path}/.claude/status.log" ]] && missing+=(".claude/status.log")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Missing configuration files:${NC}"
        for file in "${missing[@]}"; do
            echo "  - $file"
        done
        echo "Run ./scripts/setup-worktrees.sh to fix"
        return 1
    fi
    return 0
}

launch_claude_for_feature() {
    local feature="$1"
    local mode="${2:-foreground}"
    local worktree_path="${PROJECT_ROOT}/worktrees/feature-${feature}"

    if [[ ! -d "$worktree_path" ]]; then
        echo -e "${RED}Error: Worktree not found: $worktree_path${NC}"
        echo "Run ./scripts/setup-worktrees.sh first"
        exit 1
    fi

    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}Launching Claude for feature: ${feature}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""
    echo "Worktree: $worktree_path"
    echo ""

    # Verify configuration
    if ! verify_worktree_config "$worktree_path"; then
        echo ""
        read -p "Continue anyway? (y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy] ]] && exit 1
    fi

    # Show MCP configuration
    echo -e "${BOLD}MCP Servers Configured:${NC}"
    if [[ -f "${worktree_path}/.mcp.json" ]]; then
        echo "  - context7 (documentation lookup)"
        echo "  - browseruse (web research)"
    else
        echo -e "  ${YELLOW}No .mcp.json found - MCP servers may not be available${NC}"
    fi
    echo ""

    local status_log="${worktree_path}/.claude/status.log"

    # Update status log
    echo "$(date -Iseconds) [IN_PROGRESS] Claude instance starting" >> "$status_log"

    # Build the initial prompt
    local prompt=$(cat << PROMPT_EOF
You are implementing the "${feature}" feature. Start by reading your instructions:

1. Read CLAUDE.md for workflow instructions and MCP server usage
2. Read .claude/FEATURE_SPEC.md for your implementation requirements
3. Log your progress to .claude/status.log

Begin by reading these files, then start implementing according to the spec.

Remember to:
- Use context7 MCP to look up library documentation
- Use browseruse MCP for web research when needed
- Log status updates to .claude/status.log
- Stay within your feature boundary (src/${feature}/)
PROMPT_EOF
)

    cd "$worktree_path"

    case "$mode" in
        tmux)
            if ! command -v tmux &>/dev/null; then
                echo -e "${RED}Error: tmux not installed${NC}"
                exit 1
            fi
            local session_name="claude-workers"
            local window_name="${feature}"

            # Launch Claude interactively with skip permissions, then send the prompt
            local shell_cmd="cd '$worktree_path' && claude --dangerously-skip-permissions"

            # Check if session exists, create if not
            if ! tmux has-session -t "$session_name" 2>/dev/null; then
                echo "Creating tmux session: $session_name"
                tmux new-session -d -s "$session_name" -n "$window_name" "zsh -l -c \"$shell_cmd\""
            else
                # Add new window to existing session
                echo "Adding window to session: $session_name"
                tmux new-window -t "$session_name" -n "$window_name" "zsh -l -c \"$shell_cmd\""
            fi

            # Wait for window to be created and Claude to start
            local max_retries=10
            local retry=0
            while ! tmux list-windows -t "$session_name" 2>/dev/null | grep -q "$window_name"; do
                ((retry++))
                if [[ $retry -ge $max_retries ]]; then
                    echo -e "${YELLOW}Warning: Could not verify window creation${NC}"
                    break
                fi
                sleep 0.5
            done

            # Wait for Claude to fully start
            sleep 3

            # Send the prompt with retry
            for attempt in 1 2 3; do
                if tmux send-keys -t "$session_name:$window_name" "$prompt" 2>/dev/null; then
                    sleep 1
                    tmux send-keys -t "$session_name:$window_name" Enter 2>/dev/null
                    break
                fi
                sleep 1
            done

            echo -e "${GREEN}Window '$window_name' added. Attach with: tmux attach -t $session_name${NC}"
            ;;

        background)
            echo "Starting in background..."
            cd "$worktree_path"
            nohup claude -p "$prompt" --dangerously-skip-permissions > "${worktree_path}/.claude/claude.out" 2>&1 &
            local pid=$!
            echo $pid > "${worktree_path}/.claude/claude.pid"
            echo -e "${GREEN}Started with PID: $pid${NC}"
            echo "Output: ${worktree_path}/.claude/claude.out"
            ;;

        foreground|*)
            echo -e "${BOLD}Starting Claude Code...${NC}"
            echo "─────────────────────────────────────────"
            echo ""
            # Claude Code will automatically read:
            # - .mcp.json for MCP server configuration
            # - CLAUDE.md for project instructions
            # - .claude/settings.json for permissions
            claude -p "$prompt"
            ;;
    esac
}

# Parse arguments
FEATURE=""
MODE="foreground"
CHECK_MCP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            FEATURE="--all"
            shift
            ;;
        --tmux)
            MODE="tmux"
            shift
            ;;
        --background)
            MODE="background"
            shift
            ;;
        --check-mcp)
            CHECK_MCP=true
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            FEATURE="$1"
            shift
            ;;
    esac
done

# Check MCP if requested
if [[ "$CHECK_MCP" == true ]]; then
    check_mcp_servers
    exit 0
fi

# Validate feature argument
if [[ -z "$FEATURE" ]]; then
    print_usage
    exit 1
fi

# Launch
if [[ "$FEATURE" == "--all" ]]; then
    echo -e "${BOLD}Launching Claude for all features...${NC}"
    echo ""

    for worktree in "${PROJECT_ROOT}"/worktrees/feature-*; do
        if [[ -d "$worktree" ]]; then
            feature=$(basename "$worktree" | sed 's/feature-//')
            launch_claude_for_feature "$feature" "$MODE"
            if [[ "$MODE" == "foreground" ]]; then
                echo ""
                read -p "Press Enter to continue to next feature..."
            else
                sleep 2  # Stagger launches
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}All Claude instances launched!${NC}"

    if [[ "$MODE" == "tmux" ]]; then
        echo ""
        echo "Session: claude-workers"
        echo "Windows:"
        tmux list-windows -t claude-workers 2>/dev/null || echo "  (none)"
        echo ""
        echo -e "${BOLD}Attach with:${NC} tmux attach -t claude-workers"
        echo -e "${BOLD}Switch windows:${NC} Ctrl+b then 0-9 or n/p for next/prev"
    fi
else
    launch_claude_for_feature "$FEATURE" "$MODE"
fi
SCRIPT_EOF

    # ─────────────────────────────────────────────────────────────────────────
    # monitor.sh
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/scripts/monitor.sh" << 'SCRIPT_EOF'
#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREES_DIR="${PROJECT_ROOT}/worktrees"
REFRESH_INTERVAL=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

get_status_color() {
    case "$1" in
        COMPLETE)    echo -e "${GREEN}" ;;
        IN_PROGRESS) echo -e "${YELLOW}" ;;
        TESTING)     echo -e "${CYAN}" ;;
        BLOCKED)     echo -e "${RED}" ;;
        FAILED)      echo -e "${RED}" ;;
        PENDING)     echo -e "${BLUE}" ;;
        *)           echo -e "${NC}" ;;
    esac
}

print_dashboard() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}           PARALLEL DEVELOPMENT WORKFLOW MONITOR                          ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Updated: $(date '+%Y-%m-%d %H:%M:%S')                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Summary counts
    local total=0 complete=0 in_progress=0 blocked=0 pending=0

    printf "${BOLD}%-18s %-14s %-45s${NC}\n" "FEATURE" "STATUS" "LATEST UPDATE"
    echo "─────────────────────────────────────────────────────────────────────────────"

    for worktree in "${WORKTREES_DIR}"/feature-*; do
        if [[ -d "$worktree" ]]; then
            local feature=$(basename "$worktree" | sed 's/feature-//')
            local log_file="${worktree}/.claude/status.log"

            ((total++))

            if [[ -f "$log_file" ]]; then
                local last_line=$(grep -E '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' "$log_file" | tail -1)
                local status=$(echo "$last_line" | grep -oE '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' | tr -d '[]')
                local message=$(echo "$last_line" | sed 's/.*\] //' | cut -c1-43)
                local color=$(get_status_color "$status")

                # Count statuses
                case "$status" in
                    COMPLETE)    ((complete++)) ;;
                    IN_PROGRESS) ((in_progress++)) ;;
                    BLOCKED)     ((blocked++)) ;;
                    PENDING)     ((pending++)) ;;
                esac

                printf "%-18s ${color}%-14s${NC} %-45s\n" "$feature" "$status" "$message"
            else
                printf "%-18s ${RED}%-14s${NC} %-45s\n" "$feature" "NO LOG" "Status log not found"
            fi
        fi
    done

    echo ""
    echo "─────────────────────────────────────────────────────────────────────────────"
    echo -e "${BOLD}Summary:${NC} Total: $total | ${GREEN}Complete: $complete${NC} | ${YELLOW}In Progress: $in_progress${NC} | ${RED}Blocked: $blocked${NC} | ${BLUE}Pending: $pending${NC}"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  [d] <feature>  - Show detailed log for feature"
    echo "  [i] <feature>  - Show implementation log"
    echo "  [r]            - Refresh now"
    echo "  [q]            - Quit"
    echo ""
}

show_detail() {
    local feature="$1"
    local log_file="${WORKTREES_DIR}/feature-${feature}/.claude/status.log"

    if [[ -f "$log_file" ]]; then
        echo ""
        echo -e "${CYAN}═══ Status Log: ${feature} ═══${NC}"
        echo ""
        cat "$log_file"
        echo ""
    else
        echo -e "${RED}Log not found for feature: $feature${NC}"
    fi
}

show_implementation() {
    local feature="$1"
    local log_file="${WORKTREES_DIR}/feature-${feature}/.claude/implementation.log"

    if [[ -f "$log_file" ]]; then
        echo ""
        echo -e "${CYAN}═══ Implementation Log: ${feature} ═══${NC}"
        echo ""
        cat "$log_file"
        echo ""
    else
        echo -e "${RED}Implementation log not found for feature: $feature${NC}"
    fi
}

# Main loop
while true; do
    print_dashboard

    read -t $REFRESH_INTERVAL -n 1 cmd || true

    case "$cmd" in
        d)
            read -p " Feature name: " feat
            show_detail "$feat"
            read -p "Press Enter to continue..."
            ;;
        i)
            read -p " Feature name: " feat
            show_implementation "$feat"
            read -p "Press Enter to continue..."
            ;;
        r)
            continue
            ;;
        q)
            echo "Exiting monitor..."
            exit 0
            ;;
    esac
done
SCRIPT_EOF

    # ─────────────────────────────────────────────────────────────────────────
    # merge-feature.sh
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/scripts/merge-feature.sh" << 'SCRIPT_EOF'
#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <feature-name>"
    echo ""
    echo "Merges a completed feature branch into main"
    exit 1
fi

feature="$1"
worktree_path="${PROJECT_ROOT}/worktrees/feature-${feature}"
status_log="${worktree_path}/.claude/status.log"

# Check worktree exists
if [[ ! -d "$worktree_path" ]]; then
    echo "Error: Worktree not found: $worktree_path"
    exit 1
fi

# Check status is COMPLETE
if [[ -f "$status_log" ]]; then
    status=$(grep -E '\[(COMPLETE|FAILED)\]' "$status_log" | tail -1 | grep -oE '\[COMPLETE\]' || true)
    if [[ -z "$status" ]]; then
        echo "Warning: Feature is not marked as COMPLETE"
        read -p "Merge anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            exit 1
        fi
    fi
fi

echo "Merging feature: $feature"
echo ""

# Go to main worktree
cd "$PROJECT_ROOT"

# Ensure we're on main
git checkout main

# Pull latest
git pull origin main 2>/dev/null || true

# Merge feature branch
branch_name="feature/${feature}"
echo "Merging branch: $branch_name"

if git merge "$branch_name" --no-edit; then
    echo ""
    echo "Successfully merged $feature into main"

    read -p "Remove worktree? (y/N): " remove
    if [[ "$remove" =~ ^[Yy] ]]; then
        git worktree remove "$worktree_path"
        git branch -d "$branch_name"
        echo "Worktree and branch removed"
    fi
else
    echo ""
    echo "Merge conflict detected!"
    echo "Resolve conflicts and run: git merge --continue"
fi
SCRIPT_EOF

    # ─────────────────────────────────────────────────────────────────────────
    # cleanup.sh
    # ─────────────────────────────────────────────────────────────────────────
    cat > "$project_dir/scripts/cleanup.sh" << 'SCRIPT_EOF'
#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "This will remove all worktrees and feature branches."
read -p "Are you sure? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy] ]]; then
    echo "Aborted"
    exit 0
fi

cd "$PROJECT_ROOT"

# Remove all worktrees
for worktree in worktrees/feature-*; do
    if [[ -d "$worktree" ]]; then
        feature=$(basename "$worktree")
        echo "Removing worktree: $feature"
        git worktree remove "$worktree" --force 2>/dev/null || rm -rf "$worktree"
    fi
done

# Prune worktree references
git worktree prune

# Optionally remove branches
read -p "Also remove feature branches? (y/N): " remove_branches
if [[ "$remove_branches" =~ ^[Yy] ]]; then
    for branch in $(git branch | grep 'feature/'); do
        git branch -D "$branch" 2>/dev/null || true
    done
fi

echo "Cleanup complete"
SCRIPT_EOF

    # Make all scripts executable
    chmod +x "$project_dir/scripts/"*.sh

    log_success "All workflow scripts created"
}

#───────────────────────────────────────────────────────────────────────────────
# Base Source Structure
#───────────────────────────────────────────────────────────────────────────────

create_base_source() {
    local project_dir="$1"
    shift
    local features=("$@")

    log_info "Creating base source structure..."

    # Create shared types
    mkdir -p "$project_dir/src/shared"

    cat > "$project_dir/src/shared/types.ts" << 'EOF'
/**
 * Shared type definitions used across all feature modules
 */

export interface BaseEntity {
  id: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface Result<T> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}
EOF

    cat > "$project_dir/src/shared/index.ts" << 'EOF'
export * from './types';
EOF

    # Create stub directories for each feature
    for feature in "${features[@]}"; do
        mkdir -p "$project_dir/src/${feature}"
        mkdir -p "$project_dir/src/${feature}/__tests__"

        # Capitalize first letter (compatible with bash 3.x)
        local Feature="$(tr '[:lower:]' '[:upper:]' <<< ${feature:0:1})${feature:1}"

        # Create index.ts
        cat > "$project_dir/src/${feature}/index.ts" << EOF
/**
 * ${feature} module
 *
 * This is a stub implementation. The full implementation will be
 * developed in the feature worktree.
 */

export * from './${feature}.service';
export * from './${feature}.types';
EOF

        # Create types file
        cat > "$project_dir/src/${feature}/${feature}.types.ts" << EOF
/**
 * Type definitions for ${feature} module
 */

import { BaseEntity } from '../shared/types';

// TODO: [FEATURE:${feature}] Define feature-specific types

export interface ${Feature}Config {
  // Configuration options
}

export interface ${Feature}Entity extends BaseEntity {
  // Entity fields
}
EOF

        # Create service stub
        cat > "$project_dir/src/${feature}/${feature}.service.ts" << EOF
/**
 * ${feature} service - stub implementation
 *
 * TODO: [FEATURE:${feature}] Implement full service logic
 */

import { ${Feature}Config, ${Feature}Entity } from './${feature}.types';
import { Result } from '../shared/types';

export class ${Feature}Service {
  private config: ${Feature}Config;

  constructor(config: ${Feature}Config) {
    this.config = config;
  }

  /**
   * Stub method - implement in feature worktree
   */
  async initialize(): Promise<Result<void>> {
    // TODO: [FEATURE:${feature}] Implement initialization
    return { success: true };
  }
}
EOF

        # Create test stub
        cat > "$project_dir/src/${feature}/__tests__/${feature}.service.test.ts" << EOF
/**
 * Tests for ${feature} service
 *
 * TODO: [FEATURE:${feature}] Implement comprehensive tests
 */

import { ${Feature}Service } from '../${feature}.service';

describe('${Feature}Service', () => {
  let service: ${Feature}Service;

  beforeEach(() => {
    service = new ${Feature}Service({});
  });

  it('should initialize successfully', async () => {
    const result = await service.initialize();
    expect(result.success).toBe(true);
  });

  // TODO: Add more tests
});
EOF

    done

    # Create main index
    cat > "$project_dir/src/index.ts" << EOF
/**
 * Main entry point
 *
 * Re-exports all feature modules
 */

export * from './shared';
$(for feature in "${features[@]}"; do echo "export * from './${feature}';"; done)
EOF

    log_success "Base source structure created"
}

#───────────────────────────────────────────────────────────────────────────────
# Create README
#───────────────────────────────────────────────────────────────────────────────

create_readme() {
    local project_dir="$1"
    local project_name="$2"

    cat > "$project_dir/README.md" << EOF
# ${project_name}

This project uses a parallelized development workflow with multiple Claude Code instances.

## Quick Start

\`\`\`bash
# 1. Setup worktrees for all features
./scripts/setup-worktrees.sh

# 2. Launch Claude for a specific feature
./scripts/launch-claude.sh <feature-name>

# 3. Monitor all features
./scripts/monitor.sh

# 4. Merge completed features
./scripts/merge-feature.sh <feature-name>
\`\`\`

## Project Structure

\`\`\`
├── specs/
│   ├── PROJECT_SPEC.md      # Master project specification
│   └── features/            # Per-feature specifications
├── scripts/
│   ├── setup-worktrees.sh   # Create git worktrees
│   ├── launch-claude.sh     # Launch Claude instances
│   ├── monitor.sh           # Monitor progress dashboard
│   ├── merge-feature.sh     # Merge completed features
│   └── cleanup.sh           # Remove worktrees
├── src/                     # Base implementation
└── worktrees/               # Feature worktrees (gitignored)
\`\`\`

## Workflow

1. **Specification**: Edit \`specs/PROJECT_SPEC.md\` with your project details
2. **Feature Specs**: Create detailed specs in \`specs/features/\`
3. **Setup**: Run \`./scripts/setup-worktrees.sh\`
4. **Develop**: Launch Claude instances for each feature
5. **Monitor**: Use \`./scripts/monitor.sh\` to track progress
6. **Integrate**: Merge completed features with \`./scripts/merge-feature.sh\`

## MCP Servers

All Claude instances have access to the following MCP servers (configured in \`.mcp.json\`):

### context7
- **Purpose**: Library documentation and code context lookup
- **Usage**: Fetch docs for React, Express, Prisma, or any npm package
- **Config**: \`@upstash/context7-mcp\`

### browseruse
- **Purpose**: Web browser automation for research
- **Usage**: Look up API docs, verify package versions, research solutions
- **Config**: \`@anthropic/browseruse-mcp\` (headless mode enabled)

### Verifying MCP Setup
\`\`\`bash
./scripts/launch-claude.sh --check-mcp
\`\`\`

## Status Codes

| Code | Meaning |
|------|---------|
| PENDING | Not started |
| IN_PROGRESS | Active development |
| BLOCKED | Cannot proceed |
| TESTING | Running tests |
| COMPLETE | Ready for merge |
| FAILED | Needs intervention |
EOF

    log_success "README created"
}

#───────────────────────────────────────────────────────────────────────────────
# Claude Planning Phase
#───────────────────────────────────────────────────────────────────────────────

run_claude_planning() {
    local project_dir="$1"
    local project_name="$2"
    local project_description="$3"

    log_info "Launching Claude Code for project planning..."
    echo ""
    echo -e "${CYAN}Claude will analyze your project and create:${NC}"
    echo "  - Detailed project specification"
    echo "  - Feature breakdown with specs"
    echo "  - Technology recommendations"
    echo ""

    cd "$project_dir"

    # Write planning instructions to CLAUDE.md (Claude auto-reads this)
    cat > "$project_dir/CLAUDE.md" << PROMPT_EOF
# Project Planning Instructions

You are a software architect helping to plan a new project. Your task is to analyze the project requirements and create detailed specifications.

## Project Information
- **Name**: ${project_name}
- **Description**: ${project_description}

## Your Tasks

### 1. Create Project Specification
Create a comprehensive project spec at \`specs/PROJECT_SPEC.md\` that includes:
- Executive summary and goals
- System architecture (with ASCII diagrams)
- Technology stack recommendations (with rationale)
- Domain model and core entities
- Feature breakdown for parallel development
- Non-functional requirements (performance, security, scalability)

### 2. Identify Feature Modules
Break down the project into 3-7 independent feature modules that can be developed in parallel. Consider:
- Separation of concerns
- Minimal dependencies between features
- Clear boundaries and interfaces
- Each feature should be implementable by a single Claude instance

### 3. Create Feature Specifications
For each feature module, create a detailed spec file at \`specs/features/<feature-name>.spec.md\` containing:
- Feature overview and purpose
- Acceptance criteria (checkboxes)
- Technical requirements (files to create, interfaces, data models)
- External dependencies (npm packages needed)
- Testing requirements
- Definition of done

### 4. Output Feature List (CRITICAL)
**IMPORTANT**: After creating all specs, you MUST create a file at \`specs/.features\` containing ONLY the feature names (one per line, lowercase, no spaces). This file is required for the automation scripts to continue.

Example \`specs/.features\` content:
\`\`\`
auth
api
database
ui
\`\`\`

## Guidelines
- Use TypeScript/Node.js patterns unless the description suggests otherwise
- Design for testability (80% coverage target)
- Keep features loosely coupled
- Define clear interfaces between modules
- Be specific in acceptance criteria - they will guide implementation

## Start Now
Read these instructions and begin planning. Start by creating specs/PROJECT_SPEC.md, then create individual feature specs, and finally create specs/.features with the feature list.
PROMPT_EOF

    echo -e "${BOLD}Starting Claude Code planning session...${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    echo -e "${YELLOW}Instructions:${NC}"
    echo "  1. Claude will read CLAUDE.md automatically and begin planning"
    echo "  2. Watch as Claude creates the project and feature specs"
    echo "  3. When Claude finishes and creates specs/.features, exit Claude"
    echo "  4. Type /exit or press Ctrl+D to exit when done"
    echo ""
    read -p "Press Enter to start Claude..."
    echo ""

    # Launch Claude interactively - it will auto-read CLAUDE.md
    claude --dangerously-skip-permissions || true

    echo ""
    echo "─────────────────────────────────────────"

    # Check if features file was created
    if [[ ! -f "$project_dir/specs/.features" ]]; then
        log_warn "Claude did not create specs/.features file"
        echo ""

        # Try to auto-detect from specs/features directory
        if [[ -d "$project_dir/specs/features" ]] && ls "$project_dir/specs/features"/*.spec.md &>/dev/null; then
            echo "Detected feature specs in specs/features/:"
            local detected_features=()
            for spec in "$project_dir/specs/features"/*.spec.md; do
                local fname=$(basename "$spec" .spec.md)
                detected_features+=("$fname")
                echo "  - $fname"
            done
            echo ""

            if prompt_confirm "Use these features?" "y"; then
                printf '%s\n' "${detected_features[@]}" > "$project_dir/specs/.features"
            fi
        fi

        # If still no features file, ask user
        if [[ ! -f "$project_dir/specs/.features" ]]; then
            echo "Please enter the features that were planned:"

            local features=()
            while true; do
                local feature=$(prompt_input "Feature name (or Enter to finish)" "")
                if [[ -z "$feature" ]]; then
                    break
                fi
                feature=$(echo "$feature" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
                features+=("$feature")
            done

            # Write features file
            if [[ ${#features[@]} -gt 0 ]]; then
                printf '%s\n' "${features[@]}" > "$project_dir/specs/.features"
            fi
        fi
    fi

    # After planning, update CLAUDE.md for normal project use
    cat > "$project_dir/CLAUDE.md" << 'EOF'
# Claude Code Project Instructions

## MCP Servers Available

### context7
- **Purpose**: Library documentation and code context lookup
- **Usage**: Use to fetch documentation for any library/framework

### browseruse
- **Purpose**: Web browser automation and research
- **Usage**: Navigate websites, research documentation, verify APIs

## Workflow Instructions

When working on a feature in this project:

1. **Always read** `.claude/FEATURE_SPEC.md` first if it exists
2. **Log status** to `.claude/status.log` using format:
   ```
   $(date -Iseconds) [STATUS] Message
   ```
   Status codes: PENDING, IN_PROGRESS, BLOCKED, TESTING, COMPLETE, FAILED

3. **Log implementation details** to `.claude/implementation.log`

4. **Use context7** to look up documentation for libraries before using them

5. **Use browseruse** for web research when needed

## Code Standards

- Follow existing code patterns in the project
- Write tests for all new functionality (target: 80% coverage)
- Do not modify files outside your feature boundary
- Update status log at each milestone
EOF

    log_success "Planning phase complete"
}

extract_features_from_plan() {
    local project_dir="$1"
    local features_file="$project_dir/specs/.features"

    if [[ -f "$features_file" ]]; then
        # Read features from file, filter empty lines and comments
        grep -v '^#' "$features_file" | grep -v '^$' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]\n-'
    else
        # Fallback: scan specs/features directory
        if [[ -d "$project_dir/specs/features" ]]; then
            for spec in "$project_dir/specs/features"/*.spec.md; do
                if [[ -f "$spec" ]]; then
                    basename "$spec" .spec.md
                fi
            done
        fi
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Main Bootstrap Flow
#───────────────────────────────────────────────────────────────────────────────

main() {
    print_banner

    echo -e "${BOLD}Welcome to the Parallel Development Workflow Bootstrapper!${NC}"
    echo ""
    echo "This script will:"
    echo "  1. Create project directory and base structure"
    echo "  2. Launch Claude Code to analyze and plan the project"
    echo "  3. Claude will create project spec and feature breakdowns"
    echo "  4. Set up worktrees and launch parallel Claude instances"
    echo ""

    # Get project details
    local project_name=$(prompt_input "Project name" "my-project")
    local project_dir=$(prompt_input "Project directory" "$(pwd)/$project_name")

    echo ""
    echo -e "${BOLD}Describe your project:${NC}"
    echo "(Be detailed - Claude will use this to plan features and architecture)"
    echo ""
    local project_description=$(prompt_input "Project description" "")

    if [[ -z "$project_description" ]]; then
        log_error "Project description is required for Claude to plan the project"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo "─────────────────────────────────────────"
    echo "  Project Name: $project_name"
    echo "  Directory:    $project_dir"
    echo "  Description:  $project_description"
    echo "─────────────────────────────────────────"
    echo ""

    if ! prompt_confirm "Proceed with setup?" "y"; then
        log_warn "Setup cancelled"
        exit 0
    fi

    echo ""

    # Phase 1: Create base structure
    log_info "Phase 1: Creating base project structure..."
    create_directory_structure "$project_dir"
    init_git_repo "$project_dir"
    create_mcp_config "$project_dir"

    # Phase 2: Run Claude planning
    log_info "Phase 2: Running Claude Code for project planning..."
    echo ""
    run_claude_planning "$project_dir" "$project_name" "$project_description"

    # Phase 3: Extract features from Claude's plan
    log_info "Phase 3: Extracting features from plan..."
    local features=()
    while IFS= read -r feature; do
        [[ -n "$feature" ]] && features+=("$feature")
    done < <(extract_features_from_plan "$project_dir")

    if [[ ${#features[@]} -eq 0 ]]; then
        log_error "No features found. Check specs/features/ directory."
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Features identified by Claude:${NC}"
    for feature in "${features[@]}"; do
        echo "  - $feature"
    done
    echo ""

    if ! prompt_confirm "Continue with these features?" "y"; then
        log_warn "Setup cancelled"
        exit 0
    fi

    # Phase 4: Create scripts and source structure
    log_info "Phase 4: Creating workflow scripts and source structure..."
    create_scripts "$project_dir" "${features[@]}"
    create_base_source "$project_dir" "${features[@]}"
    create_readme "$project_dir" "$project_name"

    # Run MCP setup to pre-cache packages
    log_info "Pre-caching MCP server packages..."
    cd "$project_dir"
    ./scripts/setup-mcp.sh 2>/dev/null || log_warn "MCP setup had warnings (non-fatal)"

    # Initial commit
    cd "$project_dir"
    git add -A
    git commit -m "Initial project scaffold with Claude-planned architecture

Project: ${project_name}
Description: ${project_description}

Features planned by Claude:
$(for feature in "${features[@]}"; do echo "- ${feature}"; done)

Includes:
- Project specification (specs/PROJECT_SPEC.md)
- Feature specifications (specs/features/*.spec.md)
- Workflow scripts for parallel development
- Base source structure with stubs
- MCP configuration for context7 and browseruse

Co-Authored-By: Claude <noreply@anthropic.com>"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                     PROJECT PLANNING COMPLETE!                           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Claude planned the following features:${NC}"
    for feature in "${features[@]}"; do
        echo "  - $feature (specs/features/${feature}.spec.md)"
    done
    echo ""
    echo -e "${BOLD}MCP Servers Configured:${NC}"
    echo "  - context7 (library documentation lookup)"
    echo "  - browseruse (web research & automation)"
    echo ""

    # Ask if user wants to continue with worktree setup
    echo ""
    if prompt_confirm "Set up worktrees and launch Claude workers now?" "y"; then
        echo ""
        log_info "Phase 5: Setting up worktrees..."
        ./scripts/setup-worktrees.sh

        echo ""
        if prompt_confirm "Launch all Claude workers in tmux?" "y"; then
            log_info "Phase 6: Launching Claude workers..."
            ./scripts/launch-claude.sh --all --tmux

            echo ""
            echo -e "${GREEN}All Claude workers launched!${NC}"
            echo ""
            echo -e "${BOLD}To monitor progress:${NC}"
            echo "  ${CYAN}./scripts/monitor.sh${NC}"
            echo ""
            echo -e "${BOLD}To attach to workers:${NC}"
            echo "  ${CYAN}tmux attach -t claude-workers${NC}"
        fi
    else
        echo ""
        echo -e "${BOLD}Next Steps:${NC}"
        echo ""
        echo "  1. Review the specs Claude created:"
        echo "     ${CYAN}cat specs/PROJECT_SPEC.md${NC}"
        for feature in "${features[@]}"; do
            echo "     ${CYAN}cat specs/features/${feature}.spec.md${NC}"
        done
        echo ""
        echo "  2. Set up worktrees:"
        echo "     ${CYAN}./scripts/setup-worktrees.sh${NC}"
        echo ""
        echo "  3. Launch Claude workers:"
        echo "     ${CYAN}./scripts/launch-claude.sh --all --tmux${NC}"
        echo ""
        echo "  4. Monitor progress:"
        echo "     ${CYAN}./scripts/monitor.sh${NC}"
    fi

    echo ""
    echo -e "${BOLD}Project directory:${NC} $project_dir"
    echo ""
}

# Run main
main "$@"
