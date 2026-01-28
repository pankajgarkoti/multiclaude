#!/bin/bash
set -e

VERSION="1.0.0"
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

# Name validation
validate_project_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        printf "${RED}Error: Invalid name '%s'${NC}\n" "$name"
        echo "Names must start with a letter and contain only letters, numbers, hyphens, underscores."
        exit 1
    fi
    if [[ ${#name} -gt 64 ]]; then
        printf "${RED}Error: Name too long (max 64 chars)${NC}\n"
        exit 1
    fi
}

# Progress spinner
_spinner() {
    local pid=$1
    local msg="${2:-Working...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    tput civis 2>/dev/null  # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%s${NC} %s" "${spin:i++%${#spin}:1}" "$msg"
        sleep 0.1
    done
    tput cnorm 2>/dev/null  # Show cursor
    printf "\r%-$((${#msg}+3))s\r" " "  # Clear line
}

run_claude_until_complete() {
    local prompt="$1"
    local completion_id="$2"
    local output_file
    output_file=$(mktemp)

    # Create a named pipe for communication
    local pipe_dir
    pipe_dir=$(mktemp -d)
    local pipe="$pipe_dir/claude_pipe"
    mkfifo "$pipe"

    # Start claude in background, tee output to file and terminal
    (claude "$prompt" --dangerously-skip-permissions < "$pipe" 2>&1 | tee "$output_file") &
    local claude_pid=$!

    # Open pipe for writing (keep it open)
    exec 3>"$pipe"

    # Monitor output file for completion identifier
    local found=false
    local check_count=0
    local max_checks=3600  # 1 hour max (checking every second)

    while kill -0 "$claude_pid" 2>/dev/null; do
        if grep -q "$completion_id" "$output_file" 2>/dev/null; then
            found=true
            sleep 2
            echo "/exit" >&3
            sleep 1
            break
        fi

        ((check_count++))
        [[ $check_count -ge $max_checks ]] && break

        sleep 1
    done

    # Close pipe and wait for claude to finish
    exec 3>&-
    wait "$claude_pid" 2>/dev/null || true

    # Cleanup
    rm -f "$output_file" "$pipe"
    rmdir "$pipe_dir" 2>/dev/null || true

    if [[ "$found" == true ]]; then
        return 0
    else
        return 1
    fi
}

print_banner() {
    echo -e "${CYAN}${BOLD}Parallel Development Workflow${NC}"
    echo ""
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

# Prompt for multiline input using $EDITOR (like git commit)
prompt_multiline() {
    local prompt="$1"
    local tmpfile
    tmpfile=$(mktemp)

    # Add instructions as comments
    cat > "$tmpfile" << 'TEMPLATE'

# Enter your project description above this line.
# Lines starting with # are ignored.
#
# Describe what you're building, including:
# - What the project does
# - Tech stack (language, frameworks, databases)
# - Key features
# - Any specific requirements
#
# Save and exit when done. Leave empty to cancel.
TEMPLATE

    # Open editor
    local editor="${EDITOR:-${VISUAL:-nano}}"
    echo -e "${BOLD}$prompt${NC}"
    echo -e "${DIM}Opening $editor... Save and exit when done.${NC}"
    $editor "$tmpfile" </dev/tty >/dev/tty

    # Extract content (remove comment lines, preserve blank lines between paragraphs)
    local result
    result=$(grep -v '^[[:space:]]*#' "$tmpfile" | sed -e '1{/^$/d}' -e '${/^$/d}')
    rm -f "$tmpfile"

    echo "$result"
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local result

    read -p "$(echo -e "${BOLD}$prompt${NC} [${default}]: ")" result
    result="${result:-$default}"
    [[ "$result" =~ ^[Yy] ]]
}

create_directory_structure() {
    local project_dir="$1"
    mkdir -p "$project_dir"/{.multiclaude/specs/features,src,docs}
}

init_git_repo() {
    local project_dir="$1"
    cd "$project_dir"

    if [[ ! -d .git ]]; then
        git init -q
        git checkout -q -b main
    fi

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Multiclaude working directory
.multiclaude/

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
EOF
}

create_mcp_config() {
    local project_dir="$1"

    cat > "$project_dir/.multiclaude/settings.json" << 'EOF'
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
    "CLAUDE_STATUS_LOG": ".multiclaude/status.log",
    "CLAUDE_IMPL_LOG": ".multiclaude/implementation.log"
  }
}
EOF

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

1. **Always read** `.multiclaude/FEATURE_SPEC.md` first if it exists
2. **Log status** to `.multiclaude/status.log` using format:
   ```
   $(date -Iseconds) [STATUS] Message
   ```
   Status codes: PENDING, IN_PROGRESS, BLOCKED, TESTING, COMPLETE, FAILED

3. **Log implementation details** to `.multiclaude/implementation.log`

4. **Use context7** to look up documentation for libraries before using them

5. **Use browseruse** for web research when needed

## Code Standards

- Follow existing code patterns in the project
- Write tests for all new functionality
- Do not modify files outside your feature boundary
- Update status log at each milestone
EOF

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
}

create_project_spec() {
    local project_dir="$1"
    local project_name="$2"
    local project_description="$3"

    cat > "$project_dir/.multiclaude/specs/PROJECT_SPEC.md" << EOF
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
}

# create_standards() - REMOVED: now provided by phases.sh run_standards_phase()

create_feature_spec() {
    local project_dir="$1"
    local feature_id="$2"
    local feature_name="$3"
    local feature_description="$4"

    local safe_name=$(echo "$feature_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
    local spec_file="$project_dir/.multiclaude/specs/features/${safe_name}.spec.md"

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
- [ ] Status logged as COMPLETE in .multiclaude/status.log

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
    echo "$safe_name"
}

create_base_source() {
    local project_dir="$1"
    shift
    local features=("$@")

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
}

create_readme() {
    local project_dir="$1"
    local project_name="$2"

    cat > "$project_dir/README.md" << EOF
# ${project_name}

This project uses a parallelized development workflow with multiple Claude Code instances.

## Quick Start

\`\`\`bash
# Run the full development loop (orchestrator + workers)
multiclaude run .

# Auto-create GitHub PR when QA passes
multiclaude run . --auto-pr

# Check status anytime
multiclaude status .

# View logs/mailbox
multiclaude logs .

# Stop the session
multiclaude stop .
\`\`\`

## Project Structure

\`\`\`
├── .multiclaude/
│   ├── settings.json        # Claude permissions
│   ├── ALL_MERGED           # Created when features merged
│   ├── qa-report.json       # QA test results
│   ├── QA_COMPLETE          # Created when QA passes
│   ├── QA_NEEDS_FIXES       # Created when QA fails
│   ├── specs/
│   │   ├── PROJECT_SPEC.md  # Master project specification
│   │   ├── STANDARDS.md     # Quality standards for QA
│   │   ├── .features        # Feature list (one per line)
│   │   └── features/        # Per-feature specifications
│   └── worktrees/feature-*/ # Feature worktrees
│       └── .multiclaude/
│           ├── FEATURE_SPEC.md  # Feature specification
│           ├── status.log       # Worker status
│           └── inbox.md         # Commands from orchestrator
├── src/                     # Base implementation
└── CLAUDE.md                # Project instructions
\`\`\`

## Workflow

1. **Specification**: Edit \`.multiclaude/specs/PROJECT_SPEC.md\` with your project details
2. **Feature Specs**: Create detailed specs in \`.multiclaude/specs/features/\`
3. **Run**: Execute \`multiclaude run .\` to start the full workflow
4. **Monitor**: Watch the orchestrator or use \`multiclaude status .\`
5. **Complete**: Orchestrator handles merge, QA, and fix cycles automatically

## How It Works

The \`multiclaude run\` command starts a bash orchestrator that:
1. Launches worker Claude agents in tmux (one per feature)
2. Monitors worker status logs for COMPLETE status
3. When all workers complete, runs merge agent (\`claude -p\`, auto-exits)
4. After merge, runs QA agent (\`claude -p --chrome\`, auto-exits)
5. If QA fails, assigns FIX_TASK to workers via their inbox.md
6. Repeats until QA passes, then marks PROJECT_COMPLETE

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
}

# run_research_phase() - REMOVED: now provided by phases.sh

# run_claude_planning() - REMOVED: now provided by phases.sh run_spec_phase()

extract_features_from_plan() {
    local project_dir="$1"
    local features_file="$project_dir/.multiclaude/specs/.features"

    if [[ -f "$features_file" ]]; then
        # Read features from file, filter empty lines and comments
        grep -v '^#' "$features_file" | grep -v '^$' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]\n-'
    else
        # Fallback: scan .multiclaude/specs/features directory
        if [[ -d "$project_dir/.multiclaude/specs/features" ]]; then
            for spec in "$project_dir/.multiclaude/specs/features"/*.spec.md; do
                if [[ -f "$spec" ]]; then
                    basename "$spec" .spec.md
                fi
            done
        fi
    fi
}

run_noninteractive() {
    local brief_file="$1"
    local project_dir="$2"

    if [[ ! -f "$brief_file" ]]; then
        log_error "File not found: $brief_file"
        exit 1
    fi

    # Convert brief to absolute path
    brief_file="$(cd "$(dirname "$brief_file")" && pwd)/$(basename "$brief_file")"

    # Use provided directory or current directory
    if [[ -z "$project_dir" ]]; then
        project_dir="$(pwd)"
    fi

    # Convert to absolute path
    project_dir="$(cd "$project_dir" && pwd)"

    local project_name="$(basename "$project_dir")"

    log_info "Setting up project in: $project_dir"

    # Create minimal structure
    mkdir -p "$project_dir/.multiclaude"
    mkdir -p "$project_dir/.multiclaude/specs/features"

    # Copy the brief file for reference
    cp "$brief_file" "$project_dir/.multiclaude/project-brief.txt"

    # Read brief content for phases
    local brief_content
    brief_content="$(cat "$brief_file")"

    # Update .gitignore (append if exists, create if not)
    if [[ -f "$project_dir/.gitignore" ]]; then
        if ! grep -q ".multiclaude/" "$project_dir/.gitignore" 2>/dev/null; then
            cat >> "$project_dir/.gitignore" << 'EOF'

# Multiclaude working directory
.multiclaude/
EOF
        fi
    else
        cat > "$project_dir/.gitignore" << 'EOF'
# Multiclaude working directory
.multiclaude/

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
EOF
    fi

    # Create MCP config (only if not exists)
    if [[ ! -f "$project_dir/.multiclaude/settings.json" ]]; then
        cat > "$project_dir/.multiclaude/settings.json" << 'EOF'
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
  }
}
EOF
    fi

    if [[ ! -f "$project_dir/.mcp.json" ]]; then
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
    fi

    # Initialize git (only if not already a git repo)
    cd "$project_dir"
    if [[ ! -d ".git" ]]; then
        git init -q
        git checkout -q -b main
    fi

    # Run phases inline
    log_info "Running phases: research -> spec -> standards"
    if ! run_all_phases "$project_dir" "$brief_content"; then
        log_warn "Phase execution had issues — specs may need manual review"
    fi

    # Commit scaffold
    cd "$project_dir"
    git add -A
    git commit -q -m "initial scaffold from brief" 2>/dev/null || true

    log_success "Project scaffolded"

    # Launch dev session via loop.sh
    log_info "Starting development session..."
    exec "$SCRIPT_DIR/loop.sh" "$project_dir"
}

main() {
    # Cleanup trap for interrupted bootstrap
    _bootstrap_cleanup() {
        local exit_code=$?
        [[ -n "${claude_pid:-}" ]] && kill "$claude_pid" 2>/dev/null
        [[ -n "${pipe:-}" ]] && rm -f "$pipe"
        [[ -n "${pipe_dir:-}" ]] && rmdir "$pipe_dir" 2>/dev/null
        [[ -n "${output_file:-}" ]] && rm -f "$output_file"
        if [[ $exit_code -ne 0 ]]; then
            printf "\n${YELLOW}Bootstrap interrupted. Partial files may remain.${NC}\n"
        fi
    }
    trap _bootstrap_cleanup EXIT INT TERM

    # Parse command line arguments
    local arg_name=""
    local arg_dir=""
    local arg_desc=""
    local arg_from_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from-file|-f)
                arg_from_file="$2"
                shift 2
                ;;
            --name)
                arg_name="$2"
                shift 2
                ;;
            --dir)
                arg_dir="$2"
                shift 2
                ;;
            --description)
                arg_desc="$2"
                shift 2
                ;;
            -*)
                shift
                ;;
            *)
                # First positional arg is name
                if [[ -z "$arg_name" ]]; then
                    arg_name="$1"
                fi
                shift
                ;;
        esac
    done

    # Non-interactive mode - run in tmux
    if [[ -n "$arg_from_file" ]]; then
        run_noninteractive "$arg_from_file" "$arg_dir"
        exit 0
    fi

    print_banner

    # Get project details (use args if provided, otherwise prompt)
    local project_name
    if [[ -n "$arg_name" ]]; then
        project_name="$arg_name"
    else
        project_name=$(prompt_input "Project name" "my-project")
    fi

    validate_project_name "$project_name"

    local project_dir
    if [[ -n "$arg_dir" ]]; then
        project_dir="$arg_dir"
    else
        project_dir=$(prompt_input "Project directory" "$(pwd)/$project_name")
    fi

    local project_description
    if [[ -n "$arg_desc" ]]; then
        project_description="$arg_desc"
    else
        project_description=$(prompt_multiline "Project description")
    fi

    if [[ -z "$project_description" ]]; then
        log_error "Project description is required (editor was empty or cancelled)"
        exit 1
    fi

    echo ""
    echo -e "  ${BOLD}Name:${NC} $project_name"
    echo -e "  ${BOLD}Dir:${NC}  $project_dir"
    echo ""

    if ! prompt_confirm "Proceed?" "y"; then
        exit 0
    fi

    echo ""

    # Create base structure
    create_directory_structure "$project_dir"
    init_git_repo "$project_dir"
    create_mcp_config "$project_dir"

    # Run all phases: research -> spec -> standards
    if ! run_all_phases "$project_dir" "$project_description"; then
        log_warn "Phase execution failed — you can re-run phases later with 'multiclaude run'"
        echo ""
        echo -e "  ${BOLD}Project structure created at:${NC} $project_dir"
        echo ""
        echo -e "  ${BOLD}Next steps:${NC}"
        echo -e "    1. Edit specs in ${CYAN}.multiclaude/specs/${NC}"
        echo -e "    2. Run ${CYAN}multiclaude run $project_dir${NC} to start development"
        echo ""
        exit 0
    fi

    # Extract features
    local features=()
    while IFS= read -r feature; do
        [[ -n "$feature" ]] && features+=("$feature")
    done < <(extract_features_from_plan "$project_dir")

    if [[ ${#features[@]} -eq 0 ]]; then
        log_error "No features found"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Features:${NC} ${features[*]}"
    echo ""

    if ! prompt_confirm "Continue?" "y"; then
        exit 0
    fi

    create_base_source "$project_dir" "${features[@]}"
    create_readme "$project_dir" "$project_name"

    cd "$project_dir"
    git add -A
    git commit -q -m "Initial scaffold: ${project_name}

Features: ${features[*]}

Co-Authored-By: Claude <noreply@anthropic.com>"

    echo ""
    log_success "Project ready at $project_dir"
    echo ""

    if prompt_confirm "Start development loop?" "y"; then
        multiclaude run "$project_dir"
    else
        echo ""
        echo "Run: ${CYAN}multiclaude run $project_dir${NC}"
        echo ""
    fi
}

# Run main
main "$@"
