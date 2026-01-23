# Parallel Development Workflow

A system for parallelizing software development using multiple Claude Code agents, orchestrated by a supervisor daemon. Agents communicate via file-based message passing for coordination, merging, and QA.

## Overview

This workflow enables you to:

1. **Describe a project** - Provide a project name and detailed description
2. **AI-powered planning** - Claude Code analyzes and creates architecture + feature specs
3. **Parallel implementation** - Multiple Claude workers in isolated git worktrees
4. **Supervisor coordination** - A supervisor agent monitors, merges, and runs QA
5. **Continuous loop** - Automatically fix issues until all quality standards pass

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         SUPERVISOR AGENT (daemon)                           │
│                                                                             │
│   Responsibilities:                                                         │
│   - Monitor worker status (reads status.log files)                          │
│   - Merge completed features to main                                        │
│   - Back-merge main into worktrees                                          │
│   - Launch QA agent                                                         │
│   - Parse QA report and assign fix tasks                                    │
│   - Send commands to workers via message passing                            │
│   - Terminate all agents on success                                         │
└────────────────────────────────────────────────────────────────────────────┘
                    │                    │                    │
         ┌──────────┴──────────┐        │          ┌─────────┴──────────┐
         │  MESSAGE PASSING    │        │          │   MESSAGE PASSING  │
         │  (file-based)       │        │          │   (file-based)     │
         ▼                     │        ▼          │                    ▼
┌─────────────────┐            │  ┌─────────────────┐           ┌─────────────────┐
│  WORKER AGENT   │            │  │  WORKER AGENT   │           │   QA AGENT      │
│    (auth)       │            │  │    (api)        │           │   (--chrome)    │
│                 │            │  │                 │           │                 │
│  Reads:         │            │  │  Reads:         │           │  Reads:         │
│  - .claude/inbox│            │  │  - .claude/inbox│           │  - STANDARDS.md │
│  Writes:        │            │  │  Writes:        │           │  Writes:        │
│  - status.log   │            │  │  - status.log   │           │  - qa-report.json│
└─────────────────┘            │  └─────────────────┘           └─────────────────┘
         │                     │           │                             │
         └─────────────────────┴───────────┴─────────────────────────────┘
                                    │
                                    ▼
                            ┌──────────────────┐
                            │     GIT REPO     │
                            │   main branch    │
                            │   worktrees/     │
                            └──────────────────┘
```

## Installation

```bash
# Clone the repo
git clone <repo-url> workflow
cd workflow

# Install the CLI
./install.sh

# Or manually add to PATH
export PATH="$PATH:$(pwd)"
```

## Prerequisites

- **Claude Code CLI** - Installed and authenticated with Claude Max subscription
- **Git** - For version control and worktrees
- **tmux** - For running parallel Claude sessions
- **Node.js & npm** - For MCP servers

## Quick Start

### Using the `multiclaude` CLI (Recommended)

```bash
# Create a new project
multiclaude new my-app

# Run the full development loop
cd my-app
multiclaude run

# Check status
multiclaude status

# Add a feature later
multiclaude add notifications --description "Push notifications"

# Run QA
multiclaude qa
```

### Using Individual Scripts

### Option 1: Full Continuous Loop (Recommended)

```bash
# Bootstrap a project, then run the full loop
./bootstrap.sh
cd my-project
../loop.sh .
```

The loop will:
1. Setup worktrees
2. Launch all workers in tmux
3. Start supervisor daemon
4. Supervisor monitors, merges, runs QA
5. Loop continues until all standards pass

### Option 2: Step-by-Step

### 1. Bootstrap a New Project

```bash
./bootstrap.sh
```

You'll be prompted for:

- **Project name** - e.g., `task-manager`
- **Project directory** - Where to create the project
- **Project description** - Detailed description (Claude uses this to plan)

### 2. Claude Plans the Project

Claude Code launches and:

- Creates `specs/PROJECT_SPEC.md` with full architecture
- Identifies features for parallel development
- Creates `specs/features/<feature>.spec.md` for each feature
- Outputs feature list to `specs/.features`

### 3. Worktrees Are Created

The script automatically creates:

- Git branches for each feature
- Isolated worktrees in `worktrees/feature-<name>/`
- Configuration files for each Claude instance

### 4. Launch Parallel Workers

```bash
# Launch all workers in tmux
./scripts/launch-claude.sh --all --tmux

# Or launch a single worker
./scripts/launch-claude.sh auth
```

### 5. Launch Supervisor

The Supervisor Claude monitors all workers, detects issues, and reports progress:

```bash
./scripts/supervisor.sh
```

The supervisor will:

- Continuously monitor worker status
- Detect BLOCKED or FAILED workers
- Report progress to you
- Coordinate until all features complete

### 6. Or Monitor Manually

```bash
./scripts/monitor.sh
```

```
╔══════════════════════════════════════════════════════════════════════════╗
║           PARALLEL DEVELOPMENT WORKFLOW MONITOR                          ║
╠══════════════════════════════════════════════════════════════════════════╣
║ Updated: 2026-01-23 12:30:45                                             ║
╚══════════════════════════════════════════════════════════════════════════╝

FEATURE            STATUS         LATEST UPDATE
─────────────────────────────────────────────────────────────────────────────
auth               COMPLETE       All acceptance criteria met
api                TESTING        Running test suite
database           IN_PROGRESS    Implementing CRUD operations
ui                 COMPLETE       Components and tests done
notifications      BLOCKED        Waiting for api interface

Summary: Total: 5 | Complete: 2 | In Progress: 1 | Blocked: 1 | Testing: 1
```

### 6. Merge Completed Features

```bash
./scripts/merge-feature.sh auth
```

## Project Structure

After bootstrapping, your project will look like:

```
my-project/
├── .claude/
│   └── settings.json          # Claude Code permissions
├── .mcp.json                   # MCP server configuration
├── CLAUDE.md                   # Instructions Claude reads automatically
├── specs/
│   ├── PROJECT_SPEC.md        # Master project specification
│   ├── .features              # List of features (for automation)
│   └── features/
│       ├── auth.spec.md       # Feature spec for auth
│       ├── api.spec.md        # Feature spec for api
│       └── ...
├── scripts/
│   ├── setup-worktrees.sh     # Create git worktrees
│   ├── launch-claude.sh       # Launch Claude instances
│   ├── monitor.sh             # Progress dashboard
│   ├── merge-feature.sh       # Merge completed features
│   └── cleanup.sh             # Remove worktrees
├── src/
│   ├── shared/                # Shared types and utilities
│   ├── auth/                  # Feature module (stub)
│   ├── api/                   # Feature module (stub)
│   └── ...
└── worktrees/                 # Git worktrees (gitignored)
    ├── feature-auth/
    ├── feature-api/
    └── ...
```

## Quality Standards

The QA agent verifies standards defined in `specs/STANDARDS.md`. Default standards include:

| Category | ID | Standard |
|----------|-----|----------|
| Testing | STD-T001 | Unit tests pass |
| Testing | STD-T002 | Code coverage >= 80% |
| UI | STD-U001 | No console errors |
| Security | STD-S001 | No hardcoded secrets |
| Quality | STD-Q001 | No lint errors |
| Quality | STD-Q002 | TypeScript strict mode passes |

Customize `specs/STANDARDS.md` for your project's requirements.

## Templates

Templates in `workflow/templates/` define agent behavior:

| Template | Purpose |
|----------|---------|
| `SUPERVISOR.md` | Supervisor agent instructions |
| `WORKER.md` | Worker agent instructions with inbox protocol |
| `QA_INSTRUCTIONS.md` | QA agent testing procedures |
| `STANDARDS.template.md` | Default quality standards |

## MCP Servers

Each Claude instance has access to:

### context7

- **Purpose**: Library documentation lookup
- **Usage**: Fetch docs for React, Express, Prisma, etc.
- **Package**: `@upstash/context7-mcp`

### browseruse

- **Purpose**: Web browser automation
- **Usage**: Research APIs, verify documentation
- **Package**: `@anthropic/browseruse-mcp`

## Status Codes

Each Claude instance logs progress to `.claude/status.log`:

| Status        | Meaning                              |
| ------------- | ------------------------------------ |
| `PENDING`     | Worktree created, awaiting Claude    |
| `IN_PROGRESS` | Actively implementing                |
| `BLOCKED`     | Cannot proceed (dependency/question) |
| `TESTING`     | Running tests                        |
| `COMPLETE`    | All acceptance criteria met          |
| `FAILED`      | Unrecoverable error                  |

## Message Passing Protocol

Agents communicate via files in each worktree's `.claude/` directory.

### Worker → Supervisor

Workers write to `worktree/.claude/status.log`:

```
2026-01-23T10:00:00Z [IN_PROGRESS] Implementing user authentication
2026-01-23T10:30:00Z [TESTING] Running unit tests
2026-01-23T10:35:00Z [COMPLETE] All acceptance criteria met
```

### Supervisor → Worker

Supervisor writes to `worktree/.claude/inbox.md`:

```markdown
# Command: BACK_MERGE
Timestamp: 2026-01-23T10:00:00Z
Message: Main has been updated with new code.
Action: Changes merged automatically. Continue work.

---

# Command: FIX_TASK
Timestamp: 2026-01-23T11:00:00Z
Failed Standards:
- STD-U001: Console error on page load
Action: Fix the issue, commit, update status to COMPLETE.
```

### QA Agent → Supervisor

QA writes `.claude/qa-report.json` and creates either:
- `.claude/QA_COMPLETE` - All standards pass
- `.claude/QA_NEEDS_FIXES` - Failures exist

## Scripts Reference

### loop.sh

**Entry point for the continuous development loop.** Orchestrates the entire workflow.

```bash
# Full workflow
./loop.sh ./my-project

# Setup only (create worktrees, don't launch agents)
./loop.sh ./my-project --setup-only

# Launch workers only (assumes worktrees exist)
./loop.sh ./my-project --workers-only

# Launch supervisor only (assumes workers running)
./loop.sh ./my-project --supervisor

# Run QA only
./loop.sh ./my-project --qa

# Check status
./loop.sh ./my-project --status
```

### bootstrap.sh

Creates a new project with AI-powered planning.

```bash
./bootstrap.sh
```

### setup-worktrees.sh

Creates git worktrees for all features.

```bash
./scripts/setup-worktrees.sh
```

### launch-claude.sh

Launches Claude Code instances.

```bash
# Single feature (foreground)
./scripts/launch-claude.sh auth

# Single feature in tmux
./scripts/launch-claude.sh auth --tmux

# All features in tmux (parallel)
./scripts/launch-claude.sh --all --tmux

# Check MCP server status
./scripts/launch-claude.sh --check-mcp
```

### supervisor.sh

Launches the Supervisor Claude daemon that coordinates all workers.

```bash
./supervisor.sh ./my-project
# Or from within project:
../workflow/supervisor.sh .
```

The Supervisor:

- Monitors all worker status continuously
- Merges completed features to main
- Back-merges main into active worktrees
- Launches QA when all features complete
- Parses QA failures and assigns FIX_TASK commands
- Terminates when PROJECT_COMPLETE

### qa.sh

Launches the QA Agent with browser access to verify quality standards.

```bash
./qa.sh ./my-project
```

The QA Agent:

- Reads `specs/STANDARDS.md` for quality requirements
- Starts the application
- Runs tests and verifies each standard
- Writes `qa-report.json` with detailed results
- Creates `QA_COMPLETE` or `QA_NEEDS_FIXES`

### feature.sh

Adds a new feature to an existing project.

```bash
./feature.sh ./my-project notifications
./feature.sh ./my-project payments --description "Stripe payment processing"
./feature.sh ./my-project cache --deps "api,database" --launch
```

Options:
- `--description "desc"` - Feature description
- `--deps "feat1,feat2"` - Dependent features
- `--no-worktree` - Skip worktree creation
- `--launch` - Launch Claude worker after setup

### monitor.sh

Interactive dashboard for monitoring all workers (manual alternative to supervisor).

```bash
./scripts/monitor.sh
```

**Commands in monitor:**

- `d <feature>` - Show detailed status log
- `i <feature>` - Show implementation log
- `r` - Refresh now
- `q` - Quit

### merge-feature.sh

Merges a completed feature into main.

```bash
./scripts/merge-feature.sh auth
```

### cleanup.sh

Removes all worktrees and optionally feature branches.

```bash
./scripts/cleanup.sh
```

## tmux Commands

When workers are running in tmux, the session is named `claude-<project-name>`:

```bash
# Attach to the session (replace <project-name> with your project)
tmux attach -t claude-myproject

# List all tmux sessions
tmux list-sessions

# Inside tmux:
# Ctrl+b n     - Next window
# Ctrl+b p     - Previous window
# Ctrl+b 0-9   - Jump to window by number
# Ctrl+b d     - Detach (workers keep running)
# Ctrl+b w     - List all windows
```

## Best Practices

### Writing Good Project Descriptions

The better your description, the better Claude's planning:

```
❌ Bad: "A task manager app"

✅ Good: "A collaborative task management application where teams can
create projects, assign tasks to members, set due dates and priorities,
track progress with kanban boards, receive notifications for updates,
and generate productivity reports. Should support real-time updates
and have a REST API for integrations."
```

### Feature Boundaries

Claude will design features with:

- **Clear ownership** - Each feature owns specific files/directories
- **Minimal coupling** - Features communicate through defined interfaces
- **Independent testability** - Each feature can be tested in isolation

### Handling Blocked Workers

If a worker logs `BLOCKED`:

1. Check the status log: `./scripts/monitor.sh` then `d <feature>`
2. Resolve the blocking issue (usually a dependency or unclear requirement)
3. The worker will continue automatically or restart it

### Code Review

After workers complete:

1. Review each feature branch before merging
2. Check test coverage meets requirements
3. Verify interface contracts are respected
4. Run integration tests across features

## Troubleshooting

### "Invalid API key" Error

Claude Code uses your Claude Max subscription, not an API key. Make sure you're authenticated:

```bash
claude --version
```

If not logged in, the CLI will prompt you.

### Workers Not Receiving Prompts

The workers read `CLAUDE.md` automatically. If the initial prompt fails to send, workers will still work - they just need to read the spec manually.

### tmux Session Issues

```bash
# List sessions
tmux list-sessions

# Kill a stuck session (replace <project-name> with your project)
tmux kill-session -t claude-myproject

# List windows in session
tmux list-windows -t claude-myproject
```

### Worktree Conflicts

If worktree creation fails:

```bash
# Clean up worktree references
git worktree prune

# Remove stuck worktree
rm -rf worktrees/feature-<name>
git worktree prune
```

## Example Workflow

```bash
# 1. Create a new project
./bootstrap.sh
# Enter: "ecommerce-platform"
# Enter: "./ecommerce-platform"
# Enter: "An e-commerce platform with user authentication, product catalog,
#         shopping cart, checkout with Stripe, order management, and
#         inventory tracking. REST API with TypeScript/Express backend."

# 2. Claude plans and creates specs...
# 3. Review the generated specs
cat ecommerce-platform/specs/PROJECT_SPEC.md
ls ecommerce-platform/specs/features/

# 4. Launch all workers
cd ecommerce-platform
./scripts/launch-claude.sh --all --tmux

# 5. Monitor in another terminal
./scripts/monitor.sh

# 6. When all complete, merge features
./scripts/merge-feature.sh auth
./scripts/merge-feature.sh products
# ...

# 7. Run full test suite
npm test
```

## License

MIT
