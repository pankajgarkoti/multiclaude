# Parallel Development Workflow

A system for parallelizing software development using multiple Claude Code instances, each working on separate features in isolated git worktrees.

## Overview

This workflow enables you to:

1. **Describe a project** - Provide a project name and detailed description
2. **AI-powered planning** - Claude Code analyzes your description and creates:
   - Detailed project specification
   - Feature breakdown with clear boundaries
   - Individual feature specs for parallel development
3. **Parallel implementation** - Multiple Claude instances work simultaneously, each in its own git worktree
4. **Progress monitoring** - Track all workers from a central dashboard
5. **Easy integration** - Merge completed features back to main

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YOUR PROJECT IDEA                           │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CLAUDE PLANNING SESSION                          │
│  • Analyzes requirements                                            │
│  • Designs architecture                                             │
│  • Identifies 3-7 parallel features                                 │
│  • Creates detailed specs for each                                  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      GIT WORKTREES CREATED                          │
│                                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │  auth    │ │   api    │ │ database │ │    ui    │  ...         │
│  │ worktree │ │ worktree │ │ worktree │ │ worktree │              │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   PARALLEL CLAUDE INSTANCES                         │
│                                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ Claude 1 │ │ Claude 2 │ │ Claude 3 │ │ Claude 4 │  ...         │
│  │ (auth)   │ │  (api)   │ │(database)│ │   (ui)   │              │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
│       │            │            │            │                      │
│       ▼            ▼            ▼            ▼                      │
│  [COMPLETE]   [TESTING]   [IN_PROGRESS] [COMPLETE]                 │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      MERGE TO MAIN                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Claude Code CLI** - Installed and authenticated with Claude Max subscription
- **Git** - For version control and worktrees
- **tmux** - For running parallel Claude sessions
- **Node.js & npm** - For MCP servers

## Quick Start

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

### 5. Monitor Progress

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

| Status | Meaning |
|--------|---------|
| `PENDING` | Worktree created, awaiting Claude |
| `IN_PROGRESS` | Actively implementing |
| `BLOCKED` | Cannot proceed (dependency/question) |
| `TESTING` | Running tests |
| `COMPLETE` | All acceptance criteria met |
| `FAILED` | Unrecoverable error |

## Scripts Reference

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

### monitor.sh

Interactive dashboard for monitoring all workers.

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

When workers are running in tmux:

```bash
# Attach to the session
tmux attach -t claude-workers

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

# Kill a stuck session (careful!)
tmux kill-session -t claude-workers

# List windows in session
tmux list-windows -t claude-workers
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
