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

## Usage

### New Project

```bash
multiclaude new my-app
```

This creates the project and launches a tmux session with:

- **Window 0:** Monitor (control center + mailbox router)
- **Window 1:** Supervisor (coordinates everything)
- **Window 2:** QA (runs tests when signaled)
- **Window 3+:** Workers (one per feature)

### What Happens During Project Creation

1. **Research Phase**: Claude researches similar products, capturing UI/UX patterns and best practices
2. **Planning Phase**: Claude creates project specs informed by research findings
3. **Standards Generation**: Project-specific quality standards are generated (not copied from template)
4. **Development**: Supervisor coordinates workers to implement features

### Existing Project

```bash
multiclaude run ./my-app
```

### Check Status

```bash
multiclaude status ./my-app
```

### Add Feature to Existing Project

```bash
multiclaude add notifications --description "Push notifications for task updates"
```

### Attach to Running Session

```bash
multiclaude attach ./my-app
```

## Research Phase

When creating a new project, multiclaude runs a research phase that:

1. **Browses Referenced URLs**: Analyzes any URLs mentioned in your project description
2. **Researches Similar Products**: Finds and analyzes 2-3 similar products in your domain
3. **Captures UI/UX Patterns**: Documents layouts, components, user flows, and interactions
4. **Generates Informed Standards**: Creates project-specific quality standards based on findings

### Providing References for Better Results

Include URLs or product names in your project description:

```bash
multiclaude new my-app
# When prompted for description:
# "A task management app like Todoist (https://todoist.com) with calendar integration
#  similar to Notion's calendar view. Focus on clean minimal UI."
```

### Research Output

Research findings are saved to `.claude/research-findings.md` and inform:

- Project specifications (specs/PROJECT_SPEC.md)
- Feature specifications (specs/features/\*.spec.md)
- Quality standards (specs/STANDARDS.md)

## Monitor Dashboard

The monitor (Window 0) provides a live dashboard for tracking progress:

```bash
# In the monitor, type:
dashboard     # Start live auto-refreshing dashboard (every 5s)
dashboard 10  # Custom refresh interval (10 seconds)
# Press Ctrl+C to return to interactive mode
```

The dashboard shows:

- **Worker Status**: Feature name, status (PENDING/IN_PROGRESS/COMPLETE/etc), and message
- **Project Status**: Overall progress (X/Y features complete, merged, QA status)
- **Recent Messages**: Last 3 messages from the mailbox

### Monitor Commands

| Command          | Description                            |
| ---------------- | -------------------------------------- |
| `s`, `status`    | Show current status                    |
| `d`, `dashboard` | Live auto-refreshing dashboard         |
| `w`, `watch`     | Watch status with system watch command |
| `l`, `logs`      | Tail all worker status logs            |
| `m`, `messages`  | Tail the central mailbox               |
| `h`, `help`      | Show help                              |
| `q`, `quit`      | Exit monitor (agents keep running)     |

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
│   ├── mailbox                 # Central message bus
│   ├── qa-reports/             # Timestamped QA reports
│   │   ├── qa-report-2024-01-24T100000.json
│   │   ├── qa-report-2024-01-24T103000.json
│   │   └── latest.json         # Symlink to most recent
│   ├── fix-tasks/              # Timestamped fix task assignments
│   ├── SUPERVISOR.md           # Supervisor instructions
│   └── QA_INSTRUCTIONS.md      # QA instructions
├── specs/
│   ├── PROJECT_SPEC.md         # Architecture spec (informed by research)
│   ├── STANDARDS.md            # Quality standards (generated, not template)
│   ├── .features               # Feature list (one per line)
│   └── features/
│       └── *.spec.md           # Individual feature specs
├── worktrees/
│   └── feature-*/              # Isolated worktrees per feature
│       └── .claude/
│           ├── status.log      # Worker status updates
│           ├── WORKER.md       # Worker instructions
│           └── FEATURE_SPEC.md # Feature specification
└── src/                        # Source code
```

## Agent Communication

Agents communicate via a **central mailbox** (`.claude/mailbox`).

### Message Format

```
--- MESSAGE ---
timestamp: 2024-01-24T10:00:00+00:00
from: supervisor
to: qa
Your message here.
Can be multiple lines.
```

The monitor script watches the mailbox and routes messages to the appropriate agent via tmux.

### Message Flow

```
+---------------------------------------------------------------------+
|                         MESSAGE FLOW                                 |
|                                                                     |
|   +----------+     writes      +---------------+                    |
|   |  Agent   | --------------> |   MAILBOX     |                    |
|   |  (any)   |                 | .claude/mailbox|                   |
|   +----------+                 +-------+-------+                    |
|                                        |                            |
|                                        | watches                    |
|                                        v                            |
|                                +---------------+                    |
|                                |   MONITOR     |                    |
|                                |  (routes)     |                    |
|                                +-------+-------+                    |
|                                        |                            |
|                         parses [from -> to]                         |
|                                        |                            |
|                    +-------------------+-------------------+        |
|                    v                   v                   v        |
|             tmux send-keys      tmux send-keys      tmux send-keys  |
|                -t qa           -t supervisor         -t <feature>   |
|                                                                     |
+---------------------------------------------------------------------+
```

### Message Types

| Message                | From       | To         | Purpose                          |
| ---------------------- | ---------- | ---------- | -------------------------------- |
| `RUN_QA`               | supervisor | qa         | Signal QA to start testing       |
| `QA_RESULT: PASS/FAIL` | qa         | supervisor | Report test results              |
| `FIX_TASK`             | supervisor | worker     | Assign fix work after QA failure |
| `WORKER_COMPLETE`      | worker     | supervisor | Worker finished (optional)       |

### Status Codes (Worker -> Supervisor)

Workers communicate status via `.claude/status.log` (polled by supervisor):

```
PENDING      Not started
IN_PROGRESS  Working
BLOCKED      Cannot proceed
TESTING      Running tests
COMPLETE     Done, merge ready
FAILED       Error
```

## QA Reports

QA reports are timestamped and stored in `.claude/qa-reports/`:

- **Format:** `qa-report-YYYY-MM-DDTHHMMSS.json`
- **Latest:** `.claude/qa-reports/latest.json` (symlink)

This preserves history across multiple QA runs.

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

# Check mailbox router is running (in monitor window)
ps aux | grep watch_mailbox
```

## License

MIT
