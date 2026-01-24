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

    mkdir -p "$project_dir"/{.claude,specs/features,src,docs}

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
# Quality Standards Template
#───────────────────────────────────────────────────────────────────────────────

create_standards() {
    local project_dir="$1"

    log_info "Generating project-specific quality standards..."
    echo ""
    echo -e "${CYAN}Claude will generate standards based on:${NC}"
    echo "  - Research findings from .claude/research-findings.md"
    echo "  - Project specification from specs/PROJECT_SPEC.md"
    echo ""

    cd "$project_dir"

    # Create standards generation instructions
    cat > "$project_dir/CLAUDE.md" << 'STANDARDS_EOF'
# Standards Generation Instructions

You are generating quality standards for this project based on research findings and the project specification.

## Inputs to Read

1. **Research findings**: `.claude/research-findings.md` - Contains UI/UX patterns, recommended standards, and best practices from analyzed products
2. **Project specification**: `specs/PROJECT_SPEC.md` - Contains features, architecture, and requirements

Read both files before generating standards.

## Standard Format

Each standard MUST follow this exact format:

```markdown
## STD-XXX: [Descriptive Name]
**Category**: [Testing|UI|Security|CodeQuality|Performance|Documentation|Functional]

As a [user/developer], [user story format describing expected behavior or requirement].

**Verification**: [Specific command or method to verify this standard]
**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3
```

## Required Standard Categories

Include standards from ALL these categories:

### Testing (STD-T)
- Unit test coverage and passing
- Integration tests
- E2E tests if applicable

### UI (STD-U)
- Console error handling
- Responsive design
- Accessibility (a11y)
- UI patterns from research findings

### Security (STD-S)
- No hardcoded secrets
- Input validation
- Authentication/authorization if applicable

### Code Quality (STD-Q)
- Linting passes
- Type safety (TypeScript)
- Code documentation

### Performance (STD-P)
- Load times
- Bundle size
- Resource usage

### Functional (STD-F)
- Core features from PROJECT_SPEC.md
- User flows identified in research

## Your Task

1. Read `.claude/research-findings.md`
2. Read `specs/PROJECT_SPEC.md`
3. Generate `specs/STANDARDS.md` that:
   - Starts with a header and overview
   - Includes standards from ALL categories above
   - Incorporates specific insights from research (UI/UX patterns observed)
   - Adds project-specific functional standards based on features in PROJECT_SPEC
   - Contains 15-25 total standards (comprehensive but focused)
   - References analyzed products where relevant

4. When complete, say "STANDARDS_COMPLETE"

## Example Output Structure

```markdown
# Project Quality Standards

This document defines quality standards that the QA Agent will verify.
Standards are derived from research into similar products and project requirements.

## Testing Standards

### STD-T001: Unit Tests Pass
**Category**: Testing
...

## UI Standards

### STD-U001: No Console Errors
**Category**: UI
...

## Functional Standards

### STD-F001: [Feature from spec]
**Category**: Functional
...
```

Start by reading the research findings and project spec, then generate comprehensive standards.

## IMPORTANT: Exiting This Phase
When you have finished generating standards, remind the user:

**"Standards generation complete! Type /exit to proceed to the development phase."**
STANDARDS_EOF

    echo -e "${BOLD}Starting Claude Code standards generation...${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    echo -e "${YELLOW}Note: Type /exit when Claude finishes to proceed.${NC}"
    echo ""

    local gen_prompt="Read CLAUDE.md for standards generation instructions. Read the research findings and project spec, then create specs/STANDARDS.md with project-specific quality standards. Say STANDARDS_COMPLETE when done."

    claude "$gen_prompt" --dangerously-skip-permissions || true

    echo ""
    echo "─────────────────────────────────────────"

    if [[ -f "$project_dir/specs/STANDARDS.md" ]]; then
        log_success "Generated project-specific standards: specs/STANDARDS.md"
    else
        log_warn "Standards generation failed, creating fallback template"
        # Fallback to template if generation fails
        if [[ -f "$SCRIPT_DIR/templates/STANDARDS.template.md" ]]; then
            cp "$SCRIPT_DIR/templates/STANDARDS.template.md" "$project_dir/specs/STANDARDS.md"
        else
            cat > "$project_dir/specs/STANDARDS.md" << 'EOF'
# Project Quality Standards

This document defines quality standards the QA Agent will verify.

## Testing Standards

### STD-T001: Unit Tests Pass
**Category**: Testing

As a developer, all unit tests should pass before merging.

**Verification**: Run `npm test`
**Acceptance Criteria**:
- [ ] All unit tests pass
- [ ] No skipped tests without justification

### STD-T002: Code Coverage >= 80%
**Category**: Testing

As a developer, code should have adequate test coverage.

**Verification**: Run `npm test -- --coverage`
**Acceptance Criteria**:
- [ ] Line coverage >= 80%
- [ ] Branch coverage >= 70%

## UI Standards

### STD-U001: No Console Errors
**Category**: UI

As a user, I should not see console errors during normal operation.

**Verification**: Check browser console during feature usage
**Acceptance Criteria**:
- [ ] No JavaScript errors in console
- [ ] No unhandled promise rejections

## Security Standards

### STD-S001: No Hardcoded Secrets
**Category**: Security

As a developer, no sensitive data should be in source code.

**Verification**: Run `grep -r "password\|secret\|api_key" src/`
**Acceptance Criteria**:
- [ ] No API keys in source code
- [ ] No passwords in source code
- [ ] Secrets use environment variables

## Code Quality Standards

### STD-Q001: No Lint Errors
**Category**: CodeQuality

As a developer, code should follow style guidelines.

**Verification**: Run `npm run lint`
**Acceptance Criteria**:
- [ ] No ESLint errors
- [ ] No ESLint warnings (or documented exceptions)

### STD-Q002: TypeScript Strict Mode
**Category**: CodeQuality

As a developer, code should be type-safe.

**Verification**: Run `npx tsc --noEmit`
**Acceptance Criteria**:
- [ ] No TypeScript errors
- [ ] Strict mode enabled
EOF
        fi
        log_success "Fallback standards created: specs/STANDARDS.md"
    fi
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
# Run the full development loop (orchestrator + workers)
multiclaude run .

# Or step by step:
multiclaude run . --setup-only    # Setup worktrees
multiclaude run . --workers-only  # Launch workers in tmux
multiclaude run . --loop-only     # Run orchestrator loop

# Check status anytime
multiclaude status .

# Manual merge and QA (usually handled by orchestrator)
multiclaude merge .
multiclaude qa .
\`\`\`

## Project Structure

\`\`\`
├── specs/
│   ├── PROJECT_SPEC.md      # Master project specification
│   ├── STANDARDS.md         # Quality standards for QA
│   ├── .features            # Feature list (one per line)
│   └── features/            # Per-feature specifications
├── .claude/
│   ├── settings.json        # Claude permissions
│   ├── ALL_MERGED           # Created when features merged
│   ├── qa-report.json       # QA test results
│   ├── QA_COMPLETE          # Created when QA passes
│   └── QA_NEEDS_FIXES       # Created when QA fails
├── src/                     # Base implementation
├── CLAUDE.md                # Project instructions
└── worktrees/feature-*/     # Feature worktrees (gitignored)
    └── .claude/
        ├── FEATURE_SPEC.md  # Feature specification
        ├── status.log       # Worker status
        └── inbox.md         # Commands from orchestrator
\`\`\`

## Workflow

1. **Specification**: Edit \`specs/PROJECT_SPEC.md\` with your project details
2. **Feature Specs**: Create detailed specs in \`specs/features/\`
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

    log_success "README created"
}

#───────────────────────────────────────────────────────────────────────────────
# Research Phase (Runs First - Informs All Subsequent Generation)
#───────────────────────────────────────────────────────────────────────────────

run_research_phase() {
    local project_dir="$1"
    local project_name="$2"
    local project_description="$3"

    log_info "Starting research phase..."
    echo ""
    echo -e "${CYAN}Claude will research similar products and gather insights:${NC}"
    echo "  - Browse any URLs in the project description"
    echo "  - Research 2-3 similar products in this domain"
    echo "  - Capture UI/UX patterns and best practices"
    echo "  - Document findings for spec and standards generation"
    echo ""

    cd "$project_dir"
    mkdir -p "$project_dir/.claude"

    # Create research instructions in CLAUDE.md
    cat > "$project_dir/CLAUDE.md" << RESEARCH_EOF
# Research Phase Instructions

You are a RESEARCH AGENT. Your task is to gather insights that will inform this project's specifications and quality standards.

## Project Information
- **Name**: ${project_name}
- **Description**: ${project_description}

## Your Tasks

### 1. Analyze Project Description
Extract any URLs, product references, or domain-specific terminology from the description above.

### 2. Browse Referenced URLs
If the description mentions any URLs or specific products:
- Use WebFetch to analyze each referenced product/service
- Capture: features, UI patterns, UX flows, quality indicators

### 3. Research 2-3 Similar Products
Search for and analyze 2-3 similar products or competitors in this domain:
- Use WebSearch to find similar products
- Use WebFetch to analyze each product's website
- For each product, document:
  - **Features**: Core functionality, unique capabilities
  - **UI patterns**: Visual design, layouts, components, styling approaches
  - **UX patterns**: User flows, navigation, interactions, onboarding
  - **Quality aspects**: Performance indicators, accessibility, error handling

### 4. Document Your Findings
Create the file \`.claude/research-findings.md\` with this structure:

\`\`\`markdown
# Research Findings

## Project Context
[Brief summary of what we're building based on the description]

## Referenced URLs Analysis
### [URL 1]
- **Key features**: ...
- **UI patterns**: [layouts, components, visual style]
- **UX patterns**: [user flows, interactions, navigation]
- **Quality indicators**: ...

## Similar Products Analyzed

### [Product 1 Name]
- **URL**: [product URL]
- **Features**: Core functionality, unique capabilities
- **UI patterns**: Visual design, layouts, components used
- **UX patterns**: User flows, navigation structure, interactions
- **Quality aspects**: Performance, accessibility, error handling

### [Product 2 Name]
(same structure)

### [Product 3 Name]
(same structure)

## UI/UX Recommendations
Based on research, adopt these patterns:
- **[UI pattern 1]**: [description and why it's recommended]
- **[UI pattern 2]**: [description and why it's recommended]
- **[UX pattern 1]**: [description and why it's recommended]
- **[UX pattern 2]**: [description and why it's recommended]

## Recommended Standards
Based on analysis of similar products, the project should meet these standards:
- [Standard 1]: [rationale from research]
- [Standard 2]: [rationale from research]
- [Standard 3]: [rationale from research]

## Industry Best Practices
- [Best practice 1]
- [Best practice 2]
- [Best practice 3]

## Technology Observations
Common technologies/approaches used by similar products:
- [Technology/pattern 1]
- [Technology/pattern 2]
\`\`\`

### 5. Complete
When you have finished researching and documenting findings, say "RESEARCH_COMPLETE" to indicate you are done.

## Tools Available
- **WebSearch**: For finding similar products and researching the domain
- **WebFetch**: For browsing and analyzing specific URLs
- **Write/Edit**: For creating .claude/research-findings.md

## IMPORTANT: Exiting This Phase
When you are done with research, remind the user:

**"Research phase complete! Type /exit to proceed to the planning phase."**

## Start Now
Begin by analyzing the project description, then search for and analyze similar products. Document everything in .claude/research-findings.md.
RESEARCH_EOF

    echo -e "${BOLD}Starting Claude Code research session...${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    echo -e "${YELLOW}Note: Type /exit when Claude finishes research to proceed.${NC}"
    echo ""

    # Launch Claude for research
    local research_prompt="Read CLAUDE.md for your research instructions. Research similar products and create .claude/research-findings.md with your findings. Say RESEARCH_COMPLETE when done."

    claude "$research_prompt" --dangerously-skip-permissions || true

    echo ""
    echo "─────────────────────────────────────────"

    # Verify research was completed
    if [[ -f "$project_dir/.claude/research-findings.md" ]]; then
        log_success "Research findings saved to .claude/research-findings.md"
    else
        log_warn "No research findings created, will use template standards"
        # Create minimal placeholder so downstream steps don't fail
        cat > "$project_dir/.claude/research-findings.md" << 'EOF'
# Research Findings

## Project Context
Research phase was skipped or did not complete.

## Similar Products Analyzed
No products were analyzed.

## UI/UX Recommendations
Use standard industry patterns.

## Recommended Standards
Follow standard quality practices.
EOF
    fi
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

## Research Context

**IMPORTANT**: First, read the research findings from the research phase:
\`\`\`bash
cat .claude/research-findings.md
\`\`\`

Use these insights to inform your PROJECT_SPEC.md and feature specs:
- Apply UI/UX patterns observed in similar products
- Incorporate industry best practices discovered
- Reference analyzed products as inspiration
- Use recommended standards from the research

## Your Tasks

### 1. Create Project Specification
Create a comprehensive project spec at \`specs/PROJECT_SPEC.md\` that includes:
- Executive summary and goals
- **Research Insights** section summarizing key learnings from analyzed products
- System architecture (with ASCII diagrams) informed by patterns from research
- Technology stack recommendations (with rationale, referencing research)
- Domain model and core entities
- Feature breakdown for parallel development
- UI/UX patterns to adopt (from research findings)
- Non-functional requirements (performance, security, scalability)

### 2. Identify Feature Modules
Break down the project into 3-7 independent feature modules that can be developed in parallel. Consider:
- Separation of concerns
- Minimal dependencies between features
- Clear boundaries and interfaces
- Each feature should be implementable by a single Claude instance

### 3. Ask Clarifying Questions (IMPORTANT)
Before finalizing specifications, ASK THE USER about any unknowns or decisions that need their input:

**Technical Choices:**
- UI framework/library preference (React, Vue, Svelte, etc.)?
- Styling approach (Tailwind, CSS modules, styled-components)?
- State management preference?
- Database choice (if applicable)?

**API & Services:**
- Which API providers to use (authentication, payments, email, etc.)?
- Any existing APIs or services to integrate with?
- Preferred hosting/deployment platform?

**Design & UX:**
- Any specific design system or component library?
- Mobile-first or desktop-first?
- Any accessibility requirements (WCAG level)?

**Project Scope:**
- MVP vs full feature set?
- Any hard constraints or requirements?
- Timeline considerations?

Ask these questions conversationally. Wait for the user's responses before finalizing the specs. Incorporate their answers into PROJECT_SPEC.md and feature specs.

### 4. Create Feature Specifications
For each feature module, create a detailed spec file at \`specs/features/<feature-name>.spec.md\` containing:
- Feature overview and purpose
- Acceptance criteria (checkboxes)
- Technical requirements (files to create, interfaces, data models)
- External dependencies (npm packages needed)
- Testing requirements
- Definition of done

### 6. Output Feature List (CRITICAL)
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
- Incorporate user's answers to clarifying questions into all specs

## IMPORTANT: Exiting This Phase
When you have finished planning and created all specification files, remind the user:

**"Planning phase complete! All specs have been created. Type /exit to proceed to the next phase."**

## Start Now
1. First, read the research findings from .claude/research-findings.md
2. Ask the user clarifying questions about technical choices, APIs, and preferences
3. Create specs/PROJECT_SPEC.md incorporating their answers
4. Create individual feature specs in specs/features/
5. Create specs/.features with the feature list
6. Remind the user to type /exit when done
PROMPT_EOF

    echo -e "${BOLD}Starting Claude Code planning session...${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    echo -e "${YELLOW}Instructions:${NC}"
    echo "  1. Claude will ask clarifying questions about your project"
    echo "  2. Answer questions about tech stack, APIs, UI preferences, etc."
    echo "  3. Claude will create project and feature specs based on your answers"
    echo "  4. When Claude finishes and creates specs/.features, type ${BOLD}/exit${NC} to proceed"
    echo ""
    echo -e "${CYAN}Tip: Be specific with your answers - they shape the entire project!${NC}"
    echo ""
    read -p "Press Enter to start Claude..."
    echo ""

    # Initial prompt to kick off planning
    local planning_prompt="Read the CLAUDE.md file for your planning instructions, then create all the specification files as described. Start now."

    # Launch Claude interactively with the initial prompt
    claude "$planning_prompt" --dangerously-skip-permissions || true

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
    # Parse command line arguments
    local arg_name=""
    local arg_dir=""
    local arg_desc=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    print_banner

    echo -e "${BOLD}Welcome to the Parallel Development Workflow Bootstrapper!${NC}"
    echo ""
    echo "This script will:"
    echo "  1. Create project directory and base structure"
    echo "  2. Research similar products and gather UI/UX insights"
    echo "  3. Launch Claude Code to plan the project (informed by research)"
    echo "  4. Generate project-specific quality standards"
    echo "  5. Set up worktrees and launch parallel Claude instances"
    echo ""

    # Get project details (use args if provided, otherwise prompt)
    local project_name
    if [[ -n "$arg_name" ]]; then
        project_name="$arg_name"
    else
        project_name=$(prompt_input "Project name" "my-project")
    fi

    local project_dir
    if [[ -n "$arg_dir" ]]; then
        project_dir="$arg_dir"
    else
        project_dir=$(prompt_input "Project directory" "$(pwd)/$project_name")
    fi

    echo ""
    local project_description
    if [[ -n "$arg_desc" ]]; then
        project_description="$arg_desc"
    else
        echo -e "${BOLD}Describe your project:${NC}"
        echo "(Be detailed - Claude will use this to plan features and architecture)"
        echo ""
        project_description=$(prompt_input "Project description" "")
    fi

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

    # Phase 2: Research phase (runs FIRST to inform all subsequent steps)
    log_info "Phase 2: Running research phase..."
    echo ""
    run_research_phase "$project_dir" "$project_name" "$project_description"

    # Phase 3: Run Claude planning (informed by research)
    log_info "Phase 3: Running Claude Code for project planning (informed by research)..."
    echo ""
    run_claude_planning "$project_dir" "$project_name" "$project_description"

    # Phase 4: Extract features from Claude's plan
    log_info "Phase 4: Extracting features from plan..."
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

    # Phase 5: Create source structure
    log_info "Phase 5: Creating source structure..."
    create_base_source "$project_dir" "${features[@]}"

    # Phase 6: Generate standards (informed by research + spec)
    log_info "Phase 6: Generating project-specific standards..."
    echo ""
    create_standards "$project_dir"

    # Phase 7: Create README
    log_info "Phase 7: Finalizing project..."
    create_readme "$project_dir" "$project_name"

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
- Quality standards (specs/STANDARDS.md)
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

    # Ask if user wants to start the development loop
    echo ""
    if prompt_confirm "Start the full development loop now?" "y"; then
        echo ""
        log_info "Phase 8: Starting development loop..."
        multiclaude run "$project_dir"
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
        echo "  2. Start the full development loop:"
        echo "     ${CYAN}multiclaude run $project_dir${NC}"
        echo ""
        echo "  3. Or run step by step:"
        echo "     ${CYAN}multiclaude run $project_dir --setup-only${NC}    # Setup worktrees"
        echo "     ${CYAN}multiclaude run $project_dir --workers-only${NC}  # Launch workers"
        echo "     ${CYAN}multiclaude run $project_dir --loop-only${NC}     # Run orchestrator"
        echo ""
        echo "  4. Check status anytime:"
        echo "     ${CYAN}multiclaude status $project_dir${NC}"
    fi

    echo ""
    echo -e "${BOLD}Project directory:${NC} $project_dir"
    echo ""
}

# Run main
main "$@"
