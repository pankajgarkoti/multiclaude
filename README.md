# multiclaude

Parallel Claude Code development with coordinated agents. Multiple Claude instances work on features simultaneously, coordinated by a supervisor.

## Installation

```bash
git clone <repo-url> multiclaude
cd multiclaude
./install.sh
```

**Requirements:** Claude Code CLI, git, tmux

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

The Supervisor asks for your project description, creates specs and base code, then coordinates workers.

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
│   ├── mailbox                 # Central message bus
│   ├── qa-reports/             # Timestamped QA reports
│   │   ├── qa-report-2024-01-24T100000.json
│   │   ├── qa-report-2024-01-24T103000.json
│   │   └── latest.json         # Symlink to most recent
│   ├── fix-tasks/              # Timestamped fix task assignments
│   ├── SUPERVISOR.md           # Supervisor instructions
│   └── QA_INSTRUCTIONS.md      # QA instructions
├── specs/
│   ├── PROJECT_SPEC.md         # Architecture spec
│   ├── STANDARDS.md            # Quality standards
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

| Message | From | To | Purpose |
|---------|------|-----|---------|
| `RUN_QA` | supervisor | qa | Signal QA to start testing |
| `QA_RESULT: PASS/FAIL` | qa | supervisor | Report test results |
| `FIX_TASK` | supervisor | worker | Assign fix work after QA failure |
| `WORKER_COMPLETE` | worker | supervisor | Worker finished (optional) |

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
