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
- **Window 0:** Monitor (control center)
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
│   ├── supervisor-inbox.md    # Messages to supervisor
│   ├── qa-inbox.md            # Messages to QA
│   └── SUPERVISOR.md          # Supervisor instructions
├── specs/
│   ├── PROJECT_SPEC.md        # Architecture spec
│   ├── STANDARDS.md           # Quality standards
│   ├── .features              # Feature list (one per line)
│   └── features/
│       └── *.spec.md          # Individual feature specs
├── worktrees/
│   └── feature-*/             # Isolated worktrees per feature
│       └── .claude/
│           ├── inbox.md       # Commands from supervisor
│           ├── status.log     # Worker status updates
│           └── WORKER.md      # Worker instructions
└── src/                       # Source code
```

## Agent Communication

Agents communicate via file-based message passing:

| From | To | File |
|------|-----|------|
| Worker | Supervisor | `worktrees/feature-*/.claude/status.log` |
| Supervisor | Worker | `worktrees/feature-*/.claude/inbox.md` |
| Supervisor | QA | `.claude/qa-inbox.md` |
| QA | Supervisor | `.claude/qa-report.json` |

### Status Codes (Worker → Supervisor)

```
PENDING      Not started
IN_PROGRESS  Working
BLOCKED      Cannot proceed
TESTING      Running tests
COMPLETE     Done, merge ready
FAILED       Error
```

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

## License

MIT
