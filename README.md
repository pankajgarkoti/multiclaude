# multiclaude

Parallel Claude Code development with coordinated agents. Multiple Claude instances work on features simultaneously, coordinated by a supervisor.

## Installation

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/pankajgarkoti/multiclaude/main/remote-install.sh | bash
```

This will:

- Clone multiclaude to `~/.multiclaude`
- Install missing dependencies (git, tmux, claude CLI)
- Add `multiclaude` command to your PATH

### Custom install location

```bash
curl -fsSL https://raw.githubusercontent.com/pankajgarkoti/multiclaude/main/remote-install.sh | INSTALL_PATH=~/tools/multiclaude bash
```

### Manual installation

```bash
git clone https://github.com/pankajgarkoti/multiclaude.git ~/.multiclaude
cd ~/.multiclaude
./install.sh
```

### Requirements

The installer will attempt to install these automatically:

- **git** - version control
- **tmux** - terminal multiplexer for agent windows
- **claude** - Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)

Optional:

- **jq** - JSON processing (for some status commands)

## Quick Start

```bash
# Create a new project
multiclaude new my-app

# Or add a feature to any existing git repo
cd existing-repo
multiclaude add auth

# Run the development session
multiclaude run .

# With auto-PR creation when QA passes
multiclaude run . --auto-pr
```

## Usage

### New Project

```bash
# Interactive - prompts for details
multiclaude new my-app

# Non-interactive - reads from brief file
multiclaude new -f project-brief.txt
```

This runs a bootstrap process that:

1. **Research Phase**: Claude researches similar products by browsing URLs mentioned in your description and finding 2-3 competitors. Captures UI/UX patterns and best practices into `.claude/research-findings.md`
2. **Planning Phase**: Claude creates project specs (`specs/PROJECT_SPEC.md`) and individual feature specs (`specs/features/*.spec.md`) informed by research findings
3. **Standards Generation**: Project-specific quality standards are generated in `specs/STANDARDS.md`
4. **Development Loop**: Optionally launches the development session

### Add Feature

```bash
# Interactive - prompts for description
multiclaude add notifications

# Non-interactive - reads from brief file
multiclaude add -f feature-brief.txt
```

Works on any git repo - automatically bootstraps the `specs/` structure if it doesn't exist.

### Run Development Session

```bash
multiclaude run ./my-app

# Auto-create GitHub PR when QA passes (requires gh CLI)
multiclaude run ./my-app --auto-pr
```

Creates a tmux session with multiple windows:

- **Window 0:** Monitor (control center + mailbox router)
- **Window 1:** Supervisor (coordinates everything)
- **Window 2:** QA (runs tests when signaled)
- **Window 3+:** Workers (one per feature)

The monitor script handles:
- Setting up git worktrees for each feature
- Installing agent instruction templates
- Launching all Claude agents
- Routing messages between agents via the central mailbox

### Check Status

```bash
multiclaude status ./my-app
```

Displays worker status, project state, and communication file status.

### Attach to Running Session

```bash
multiclaude attach ./my-app
```

### Restart Monitor

```bash
multiclaude monitor ./my-app
```

Restarts the monitor script in an existing tmux session (useful if the monitor crashed).

### Reinstall/Update

```bash
multiclaude install
```

Runs the installer to check dependencies and update the symlink.

## Research Phase

When creating a new project with `multiclaude new`, an interactive research phase runs:

1. **Analyzes Project Description**: Extracts URLs, product references, and domain terminology
2. **Browses Referenced URLs**: Uses WebFetch to analyze mentioned products/services
3. **Researches Similar Products**: Searches for and analyzes 2-3 competitors in the domain
4. **Documents Findings**: Creates `.claude/research-findings.md` with UI/UX patterns, features, and recommendations

### Providing References for Better Results

Include URLs or product names in your project description:

```bash
multiclaude new my-app
# When prompted for description:
# "A task management app like Todoist (https://todoist.com) with calendar integration
#  similar to Notion's calendar view. Focus on clean minimal UI."
```

### Research Output

Research findings inform the planning phase and are saved to `.claude/research-findings.md`.

## Monitor Dashboard

The monitor (Window 0) automatically runs a live dashboard showing:

- **Worker Status**: Feature name, status code, and latest message
- **Project Status**: Overall progress and completion markers
- **Recent Messages**: Last 5 messages from the mailbox

The dashboard auto-refreshes every 5 seconds. Press `Ctrl+C` once to see a warning (agents keep running), press again to quit the monitor.

## tmux Navigation

```
Ctrl+b 0    Monitor window
Ctrl+b 1    Supervisor
Ctrl+b 2    QA
Ctrl+b 3+   Workers
Ctrl+b n/p  Next/Previous window
Ctrl+b d    Detach (agents keep running)
```

## Project Structure

```
my-project/
├── .claude/
│   ├── settings.json          # Claude permissions
│   ├── research-findings.md   # Research phase output (UI/UX insights)
│   ├── mailbox                # Central message bus for agent communication
│   ├── qa-reports/            # QA report storage
│   ├── fix-tasks/             # Fix task assignments
│   ├── SUPERVISOR.md          # Supervisor agent instructions
│   ├── QA_INSTRUCTIONS.md     # QA agent instructions
│   ├── ALL_MERGED             # Marker: all features merged to main
│   ├── QA_COMPLETE            # Marker: QA passed
│   ├── QA_NEEDS_FIXES         # Marker: QA found issues
│   └── PROJECT_COMPLETE       # Marker: project finished
├── specs/
│   ├── PROJECT_SPEC.md        # Architecture spec (informed by research)
│   ├── STANDARDS.md           # Quality standards for QA verification
│   ├── .features              # Feature list (one per line)
│   └── features/
│       └── *.spec.md          # Individual feature specs
├── worktrees/
│   └── feature-*/             # Isolated git worktrees per feature
│       └── .claude/
│           ├── status.log     # Worker status updates
│           ├── WORKER.md      # Worker instructions
│           └── FEATURE_SPEC.md # Copy of feature specification
├── src/                       # Source code (stub modules created per feature)
├── CLAUDE.md                  # Project-wide Claude instructions
└── .mcp.json                  # MCP server configuration
```

## Agent Communication

Agents communicate via a **central mailbox** (`.claude/mailbox`). The monitor script watches the mailbox and routes messages to the appropriate agent window via tmux.

### Message Format

```
--- MESSAGE ---
timestamp: 2024-01-24T10:00:00+00:00
from: supervisor
to: qa
Your message here.
Can be multiple lines.
```

### Message Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                       MESSAGE FLOW                               │
│                                                                 │
│  ┌─────────┐     writes      ┌──────────────┐                   │
│  │  Agent  │ ─────────────▶  │   MAILBOX    │                   │
│  │  (any)  │                 │.claude/mailbox│                  │
│  └─────────┘                 └──────┬───────┘                   │
│                                     │                           │
│                                     │ watches (every 2s)        │
│                                     ▼                           │
│                              ┌──────────────┐                   │
│                              │   MONITOR    │                   │
│                              │  (routes)    │                   │
│                              └──────┬───────┘                   │
│                                     │                           │
│                        parses [from -> to]                      │
│                                     │                           │
│               ┌─────────────────────┼─────────────────────┐     │
│               ▼                     ▼                     ▼     │
│        tmux send-keys        tmux send-keys        tmux send-keys│
│           -t qa             -t supervisor          -t <feature>  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Status Codes

Workers log status to `.claude/status.log` in the format: `<timestamp> [STATUS] message`

| Status        | Meaning                    |
| ------------- | -------------------------- |
| `PENDING`     | Not started                |
| `IN_PROGRESS` | Active development         |
| `BLOCKED`     | Cannot proceed             |
| `TESTING`     | Running tests              |
| `COMPLETE`    | Ready for merge            |
| `FAILED`      | Needs intervention         |

## Troubleshooting

### tmux Session Issues

```bash
tmux list-sessions                    # List all sessions
tmux attach -t claude-myproject       # Attach to session
tmux kill-session -t claude-myproject # Kill stuck session
```

### Worktree Conflicts

```bash
git worktree prune
rm -rf worktrees/feature-<name>
```

### Mailbox Issues

```bash
# View recent messages
tail -50 .claude/mailbox
```

### Monitor Not Running

If the monitor window shows a shell prompt instead of the dashboard:

```bash
multiclaude monitor ./my-project
```

## Scripts Reference

| Script             | Purpose                                                  |
| ------------------ | -------------------------------------------------------- |
| `multiclaude`      | Main CLI entry point                                     |
| `bootstrap.sh`     | Creates new project (research, planning, scaffolding)    |
| `loop.sh`          | Creates tmux session and delegates to monitor.sh         |
| `monitor.sh`       | Sets up worktrees, launches agents, runs dashboard       |
| `feature.sh`       | Adds a new feature to existing project                   |
| `install.sh`       | Installs dependencies and creates symlink                |
| `remote-install.sh`| One-liner installer (clones repo then runs install.sh)   |

## License

MIT
