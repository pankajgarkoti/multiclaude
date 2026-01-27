# Parallel Feature Development Workflow Specification

## Overview

This document defines a structured workflow for parallelized feature development using Claude Code instances across git worktrees. The workflow emphasizes separation of concerns, continuous improvement via the Ralph plugin, and centralized monitoring through a parent orchestrator session.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Phase 1: Project Specification](#phase-1-project-specification)
3. [Phase 2: Base Project Scaffold](#phase-2-base-project-scaffold)
4. [Phase 3: Feature Specification Generation](#phase-3-feature-specification-generation)
5. [Phase 4: Worktree Setup & Claude Deployment](#phase-4-worktree-setup--claude-deployment)
6. [Phase 5: Monitoring & Orchestration](#phase-5-monitoring--orchestration)
7. [MCP Configuration](#mcp-configuration)
8. [Log File Specification](#log-file-specification)
9. [Directory Structure](#directory-structure)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    PARENT CLAUDE SESSION                        │
│                      (Orchestrator)                             │
│  - Monitors all worktree status files                           │
│  - Coordinates feature integration                              │
│  - Handles cross-feature dependencies                           │
└─────────────────────┬───────────────────────────────────────────┘
                      │ monitors
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    WORKTREE DIRECTORY                           │
│  /project-root/                                                 │
│  ├── main/                 (base implementation)                │
│  ├── .multiclaude/worktrees/                                                 │
│  │   ├── feature-auth/     ◄── Claude Instance #1               │
│  │   ├── feature-api/      ◄── Claude Instance #2               │
│  │   ├── feature-ui/       ◄── Claude Instance #3               │
│  │   └── feature-db/       ◄── Claude Instance #4               │
│  └── specs/                                                     │
│      ├── PROJECT_SPEC.md                                        │
│      └── features/                                              │
│          ├── auth.spec.md                                       │
│          ├── api.spec.md                                        │
│          ├── ui.spec.md                                         │
│          └── db.spec.md                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    MCP SERVERS (All Instances)                  │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │  context7    │  │  browseruse  │                             │
│  │  MCP Server  │  │  MCP Server  │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Project Specification

### Objective
Create a comprehensive project specification with clear separation of concerns.

### Deliverable: `.multiclaude/specs/PROJECT_SPEC.md`

### Structure

```markdown
# Project Specification: [Project Name]

## 1. Executive Summary
- Project purpose
- Target users
- Key value proposition

## 2. System Architecture
- High-level architecture diagram
- Technology stack decisions
- Infrastructure requirements

## 3. Domain Model
- Core entities and relationships
- Data flow diagrams
- State management approach

## 4. Feature Modules (Separation of Concerns)
### 4.1 [Feature Module A]
- Responsibility boundary
- Public interfaces
- Dependencies (internal/external)
- Data ownership

### 4.2 [Feature Module B]
- ...

## 5. Cross-Cutting Concerns
- Authentication/Authorization
- Logging and monitoring
- Error handling strategy
- Configuration management

## 6. Integration Points
- External APIs
- Internal module communication
- Event/message contracts

## 7. Non-Functional Requirements
- Performance targets
- Security requirements
- Scalability considerations

## 8. Development Guidelines
- Code style and conventions
- Testing requirements
- Documentation standards
```

### Separation of Concerns Principles

| Concern | Isolation Strategy |
|---------|-------------------|
| **Data Access** | Repository pattern, isolated data layer |
| **Business Logic** | Service layer, pure functions where possible |
| **Presentation** | Component-based, no business logic |
| **Infrastructure** | Adapter pattern, dependency injection |
| **Cross-Cutting** | Middleware/interceptors, aspect-oriented |

---

## Phase 2: Base Project Scaffold

### Objective
Create a surface-level implementation with all module boundaries defined but minimal internal logic.

### Implementation Checklist

- [ ] Project structure with all directories
- [ ] Package/dependency configuration
- [ ] Interface definitions for all modules
- [ ] Stub implementations returning mock data
- [ ] Basic routing/entry points configured
- [ ] Shared types/contracts defined
- [ ] Development tooling configured (linting, formatting)
- [ ] CI/CD pipeline skeleton
- [ ] Environment configuration templates

### Base Implementation Standards

```
Each module should have:
├── index.ts          # Public exports only
├── types.ts          # Type definitions
├── interfaces.ts     # Contract definitions
├── [name].service.ts # Stub service with TODO markers
├── [name].repo.ts    # Stub repository (if applicable)
└── __tests__/        # Test file skeletons
```

### Stub Implementation Pattern

```typescript
// Example stub implementation
export class AuthService implements IAuthService {
  async authenticate(credentials: Credentials): Promise<AuthResult> {
    // TODO: [FEATURE:auth] Implement actual authentication
    return {
      success: true,
      token: 'stub-token',
      user: { id: 'stub-user', email: credentials.email }
    };
  }
}
```

---

## Phase 3: Feature Specification Generation

### Objective
Generate detailed feature specifications from the project spec for parallel development.

### Feature Spec Template: `.multiclaude/specs/features/[feature-name].spec.md`

```markdown
# Feature Specification: [Feature Name]

## Meta
- **Feature ID**: FEAT-XXX
- **Module**: [module-name]
- **Dependencies**: [list of dependent features/modules]
- **Estimated Complexity**: [Low/Medium/High]

## 1. Overview
Brief description of the feature and its purpose.

## 2. Acceptance Criteria
- [ ] AC-1: Description
- [ ] AC-2: Description
- [ ] AC-3: Description

## 3. Technical Requirements

### 3.1 Files to Modify/Create
| File Path | Action | Description |
|-----------|--------|-------------|
| `src/auth/auth.service.ts` | Modify | Implement authenticate() |
| `src/auth/token.util.ts` | Create | JWT token utilities |

### 3.2 Interface Contracts
```typescript
// Interfaces this feature must implement
interface IAuthService {
  authenticate(creds: Credentials): Promise<AuthResult>;
  refresh(token: string): Promise<AuthResult>;
  revoke(token: string): Promise<void>;
}
```

### 3.3 Data Models
Define any new or modified data structures.

### 3.4 External Dependencies
- Libraries to install
- External services to integrate

## 4. Implementation Notes
- Edge cases to handle
- Performance considerations
- Security considerations

## 5. Testing Requirements
- Unit test scenarios
- Integration test scenarios
- Test data requirements

## 6. Definition of Done
- [ ] All acceptance criteria met
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] No linting errors
- [ ] Documentation updated
- [ ] Status logged to `.multiclaude/status.log`
```

---

## Phase 4: Worktree Setup & Claude Deployment

### 4.1 Worktree Creation Script

```bash
#!/bin/bash
# scripts/setup-worktrees.sh

PROJECT_ROOT=$(pwd)
FEATURES=("auth" "api" "ui" "db")  # Customize per project

# Ensure main branch is up to date
git checkout main
git pull origin main

# Create worktrees directory
mkdir -p worktrees

for feature in "${FEATURES[@]}"; do
    BRANCH_NAME="feature/${feature}"
    WORKTREE_PATH="${PROJECT_ROOT}/.multiclaude/worktrees/feature-${feature}"

    # Create branch if it doesn't exist
    git branch "${BRANCH_NAME}" 2>/dev/null || true

    # Create worktree
    git worktree add "${WORKTREE_PATH}" "${BRANCH_NAME}"

    # Create .claude directory for status tracking
    mkdir -p "${WORKTREE_PATH}/.claude"

    # Initialize status log
    cat > "${WORKTREE_PATH}/.multiclaude/status.log" << EOF
# Claude Status Log - Feature: ${feature}
# Format: [TIMESTAMP] [STATUS] [MESSAGE]
# Status: PENDING | IN_PROGRESS | BLOCKED | TESTING | COMPLETE | FAILED

$(date -Iseconds) PENDING Worktree initialized, awaiting Claude instance
EOF

    # Copy feature spec to worktree
    cp "specs/features/${feature}.spec.md" "${WORKTREE_PATH}/.multiclaude/FEATURE_SPEC.md"

    echo "Created worktree for feature: ${feature}"
done

echo "All worktrees created successfully"
```

### 4.2 Claude Instance Launch Script

```bash
#!/bin/bash
# scripts/launch-claude-instances.sh

PROJECT_ROOT=$(pwd)
WORKTREES_DIR="${PROJECT_ROOT}/worktrees"

# Claude Code launch command template
launch_claude() {
    local feature=$1
    local worktree_path="${WORKTREES_DIR}/feature-${feature}"
    local spec_path="${worktree_path}/.multiclaude/FEATURE_SPEC.md"
    local log_path="${worktree_path}/.multiclaude/status.log"

    # Launch Claude Code in new terminal/tmux pane
    # Adjust command based on your terminal setup

    claude --mcp context7 --mcp browseruse \
           --plugin ralph \
           --cwd "${worktree_path}" \
           --prompt "$(cat << EOF
You are implementing a feature in a parallelized development workflow.

## Your Assignment
- Feature: ${feature}
- Specification: Read .multiclaude/FEATURE_SPEC.md
- Status Log: Write progress to .multiclaude/status.log

## Instructions
1. Read the feature specification thoroughly
2. Update status.log with: IN_PROGRESS Starting implementation
3. Implement according to spec, following existing code patterns
4. Use Ralph plugin for continuous improvement suggestions
5. Write tests as specified
6. Update status.log at each milestone
7. On completion: COMPLETE All acceptance criteria met

## Status Log Format
$(date -Iseconds) [STATUS] [Message]

## Available MCP Servers
- context7: Use for codebase context and documentation
- browseruse: Use for web research and API documentation

## Important
- Do NOT modify files outside your feature boundary
- Respect interface contracts defined in spec
- Ask for clarification via status.log if blocked
EOF
)"
}

# Launch instances for all features
for worktree in "${WORKTREES_DIR}"/feature-*; do
    feature=$(basename "$worktree" | sed 's/feature-//')
    launch_claude "$feature" &
    sleep 2  # Stagger launches
done

echo "All Claude instances launched"
```

### 4.3 Claude Instance Configuration

Each Claude instance runs with:

```yaml
# .multiclaude/config.yaml (per worktree)
mcp_servers:
  - name: context7
    enabled: true
    config:
      # context7 specific configuration

  - name: browseruse
    enabled: true
    config:
      # browseruse specific configuration

plugins:
  - name: ralph
    enabled: true
    config:
      continuous_improvement: true
      suggest_refactors: true
      code_quality_checks: true

settings:
  auto_commit: false
  status_log: .multiclaude/status.log
  feature_spec: .multiclaude/FEATURE_SPEC.md
```

---

## Phase 5: Monitoring & Orchestration

### 5.1 Parent Session Monitoring Script

```bash
#!/bin/bash
# scripts/monitor-worktrees.sh

PROJECT_ROOT=$(pwd)
WORKTREES_DIR="${PROJECT_ROOT}/worktrees"
MONITOR_INTERVAL=30  # seconds

print_status() {
    clear
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           PARALLEL DEVELOPMENT WORKFLOW MONITOR                   ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║ Updated: $(date '+%Y-%m-%d %H:%M:%S')                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    for worktree in "${WORKTREES_DIR}"/feature-*; do
        feature=$(basename "$worktree" | sed 's/feature-//')
        log_file="${worktree}/.multiclaude/status.log"

        if [[ -f "$log_file" ]]; then
            latest_status=$(tail -1 "$log_file" | grep -oE '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' | tr -d '[]')
            latest_message=$(tail -1 "$log_file" | sed 's/.*\] //')

            # Color coding
            case "$latest_status" in
                COMPLETE)   color="\033[32m" ;;  # Green
                IN_PROGRESS) color="\033[33m" ;; # Yellow
                TESTING)    color="\033[36m" ;;  # Cyan
                BLOCKED)    color="\033[31m" ;;  # Red
                FAILED)     color="\033[31m" ;;  # Red
                *)          color="\033[37m" ;;  # White
            esac

            printf "│ %-15s │ ${color}%-12s\033[0m │ %-35s │\n" \
                   "$feature" "$latest_status" "${latest_message:0:35}"
        fi
    done

    echo ""
    echo "Commands: [r]efresh | [d]etails <feature> | [m]erge <feature> | [q]uit"
}

# Main monitoring loop
while true; do
    print_status
    read -t $MONITOR_INTERVAL -n 1 cmd

    case "$cmd" in
        r) continue ;;
        d)
            read -p "Feature name: " feat
            cat "${WORKTREES_DIR}/feature-${feat}/.multiclaude/status.log"
            read -p "Press enter to continue..."
            ;;
        m)
            read -p "Feature to merge: " feat
            # Trigger merge workflow
            ;;
        q) exit 0 ;;
    esac
done
```

### 5.2 Parent Claude Session Instructions

```markdown
# Parent Orchestrator Session Instructions

You are the orchestrator for a parallel feature development workflow.

## Your Responsibilities

1. **Monitor Progress**
   - Periodically check `.multiclaude/status.log` in each worktree
   - Track overall project completion percentage
   - Identify blocked or failed features

2. **Coordinate Dependencies**
   - When Feature A depends on Feature B, ensure B completes first
   - Facilitate interface contract updates if needed
   - Resolve cross-feature conflicts

3. **Handle Blockers**
   - When a feature logs BLOCKED status, investigate
   - Provide guidance or escalate to human if needed
   - Update relevant specs if requirements unclear

4. **Manage Integration**
   - When features complete, coordinate merge order
   - Run integration tests after merges
   - Handle merge conflicts

5. **Quality Assurance**
   - Verify all acceptance criteria met before marking complete
   - Ensure test coverage requirements satisfied
   - Check for cross-cutting concern compliance

## Monitoring Commands

```bash
# Check all status logs
for f in worktrees/feature-*/.multiclaude/status.log; do echo "=== $f ===" && tail -5 "$f"; done

# Watch for changes
watch -n 10 'for f in worktrees/feature-*/.multiclaude/status.log; do tail -1 "$f"; done'

# Get detailed status for a feature
cat worktrees/feature-auth/.multiclaude/status.log
```

## Integration Workflow

1. Feature reports COMPLETE
2. Pull latest main into feature branch
3. Run full test suite
4. If passing, merge to main
5. Update other worktrees with new main
```

---

## MCP Configuration

All Claude Code instances are configured with MCP (Model Context Protocol) servers for enhanced capabilities.

### Configuration File: `.mcp.json`

Place this file in the project root. It will be copied to each worktree:

```json
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
```

### Available MCP Servers

#### context7 MCP
- **Package**: `@upstash/context7-mcp`
- **Purpose**: Library documentation and code context lookup
- **Use Cases**:
  - Fetch documentation for npm packages (React, Express, Prisma, etc.)
  - Look up API references
  - Get usage examples for libraries
- **Example Usage in Claude**: "Use context7 to look up the Prisma schema documentation"

#### browseruse MCP
- **Package**: `@anthropic/browseruse-mcp`
- **Purpose**: Web browser automation for research
- **Use Cases**:
  - Navigate to API documentation websites
  - Research implementation patterns
  - Verify package versions and compatibility
  - Troubleshoot by searching for solutions
- **Configuration**:
  - `BROWSERUSE_HEADLESS=true` - Runs without GUI (faster, less resources)
- **Example Usage in Claude**: "Use browseruse to check the latest version of lodash"

### Claude Code Configuration Files

Each worktree contains these configuration files:

| File | Purpose |
|------|---------|
| `.mcp.json` | MCP server definitions (root level) |
| `.multiclaude/settings.json` | Claude Code permissions and settings |
| `CLAUDE.md` | Instructions Claude reads automatically |
| `.multiclaude/FEATURE_SPEC.md` | Feature-specific implementation spec |
| `.multiclaude/status.log` | Progress tracking log |

### CLAUDE.md - Automatic Instructions

Claude Code automatically reads `CLAUDE.md` from the project root. This file should contain:
- MCP server usage instructions
- Workflow requirements
- Logging format specifications
- Feature boundaries

Example structure:
```markdown
# Claude Code Instructions - Feature: auth

## MCP Servers Available
- context7: Use for documentation lookup
- browseruse: Use for web research

## Required Workflow
1. Read .multiclaude/FEATURE_SPEC.md first
2. Log status to .multiclaude/status.log
3. Stay within src/auth/ directory
```

### Verifying MCP Setup

Before launching Claude instances, verify MCP servers are available:

```bash
./scripts/launch-claude.sh --check-mcp
```

### Per-Worktree Overrides

To customize MCP config for a specific feature, edit the `.mcp.json` in that worktree:

```
worktrees/feature-auth/.mcp.json
```

---

## Log File Specification

### Status Log Format: `.multiclaude/status.log`

```
# Claude Status Log - Feature: [feature-name]
# Auto-generated, do not edit manually unless debugging

[ISO-8601-TIMESTAMP] [STATUS] [MESSAGE]
```

### Status Codes

| Code | Meaning | Action Required |
|------|---------|-----------------|
| `PENDING` | Awaiting start | None |
| `IN_PROGRESS` | Active development | None |
| `BLOCKED` | Cannot proceed | Parent investigation |
| `TESTING` | Running tests | None |
| `COMPLETE` | All criteria met | Ready for merge |
| `FAILED` | Unrecoverable error | Manual intervention |

### Example Status Log

```log
# Claude Status Log - Feature: auth
# Auto-generated

2024-01-15T10:00:00Z PENDING Worktree initialized
2024-01-15T10:05:23Z IN_PROGRESS Starting implementation - reading spec
2024-01-15T10:15:45Z IN_PROGRESS Implementing authenticate() method
2024-01-15T10:30:12Z IN_PROGRESS Adding JWT token generation
2024-01-15T10:45:00Z BLOCKED Need clarification on token expiry policy
2024-01-15T11:00:00Z IN_PROGRESS Clarification received, continuing
2024-01-15T11:30:00Z TESTING Running unit tests
2024-01-15T11:35:00Z IN_PROGRESS Fixing test failures - 2 edge cases
2024-01-15T11:50:00Z TESTING All unit tests passing
2024-01-15T12:00:00Z TESTING Running integration tests
2024-01-15T12:10:00Z COMPLETE All acceptance criteria met, ready for review
```

### Implementation Log: `.multiclaude/implementation.log`

Detailed log of changes made:

```log
# Implementation Log - Feature: auth

## Files Modified
- src/auth/auth.service.ts: Implemented authenticate(), refresh(), revoke()
- src/auth/token.util.ts: Created JWT utilities
- src/auth/__tests__/auth.service.test.ts: Added 15 test cases

## Dependencies Added
- jsonwebtoken@9.0.0
- @types/jsonwebtoken@9.0.0

## Ralph Suggestions Applied
- Refactored token validation to use dedicated middleware
- Added input sanitization for credentials
- Improved error messages for auth failures

## Test Coverage
- Unit: 94%
- Integration: 87%

## Notes
- Token expiry set to 1h (configurable via env)
- Refresh tokens stored in Redis (see api feature for Redis setup)
```

---

## Directory Structure

```
project-root/
├── .git/
├── .multiclaude/
│   ├── mcp_config.json          # Global MCP configuration
│   └── workflow_config.yaml     # Workflow settings
│
├── .multiclaude/specs/
│   ├── PROJECT_SPEC.md          # Master project specification
│   └── features/
│       ├── auth.spec.md
│       ├── api.spec.md
│       ├── ui.spec.md
│       └── db.spec.md
│
├── scripts/
│   ├── setup-worktrees.sh       # Creates all worktrees
│   ├── launch-claude-instances.sh
│   ├── monitor-worktrees.sh
│   └── merge-feature.sh
│
├── src/                         # Base implementation (main branch)
│   ├── auth/
│   ├── api/
│   ├── ui/
│   └── db/
│
├── .multiclaude/worktrees/                   # Git worktrees (gitignored)
│   ├── feature-auth/
│   │   ├── .multiclaude/
│   │   │   ├── FEATURE_SPEC.md
│   │   │   ├── status.log
│   │   │   ├── implementation.log
│   │   │   └── mcp_overrides.json
│   │   └── src/...
│   │
│   ├── feature-api/
│   │   └── ...
│   │
│   ├── feature-ui/
│   │   └── ...
│   │
│   └── feature-db/
│       └── ...
│
├── .gitignore
├── package.json
└── README.md
```

---

## Appendix A: Quick Reference Commands

```bash
# Setup
./scripts/setup-worktrees.sh

# Launch all Claude instances
./scripts/launch-claude-instances.sh

# Monitor progress
./scripts/monitor-worktrees.sh

# Check specific feature status
cat worktrees/feature-auth/.multiclaude/status.log

# Merge completed feature
./scripts/merge-feature.sh auth

# Clean up worktrees
git worktree list
git worktree remove worktrees/feature-auth

# Reset a stuck feature
git worktree remove worktrees/feature-auth --force
git worktree add worktrees/feature-auth feature/auth
```

## Appendix B: Troubleshooting

| Issue | Solution |
|-------|----------|
| Claude instance not updating log | Check MCP connections, verify write permissions |
| Feature stuck in BLOCKED | Check log for blocker message, provide clarification |
| Merge conflicts | Parent session coordinates resolution |
| MCP server not responding | Restart MCP server, check API keys |
| Worktree corrupted | Remove and recreate worktree |

---

*Document Version: 1.0*
*Last Updated: 2024-01-15*
