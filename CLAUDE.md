# CLAUDE.md

## Project

multiclaude — parallel Claude Code development orchestrator. Bash scripts that coordinate multiple Claude instances working on features simultaneously via tmux and git worktrees.

## Architecture

- `multiclaude` — CLI entrypoint, parses subcommands and dispatches to `cmd_*` functions
- `bootstrap.sh` — project scaffolding (`multiclaude new`)
- `feature.sh` — feature creation (`multiclaude add`)
- `monitor.sh` — supervisor dashboard, launches workers, monitors progress
- `loop.sh` — per-worker loop driving each Claude instance
- `phases.sh` — spec enrichment and phase runners (e.g. `run_spec_phase`)
- `install.sh` / `remote-install.sh` — local and remote installers
- `templates/` — prompt templates for workers, supervisor, QA

## Key design rules

### Spec enrichment runs once in monitor.sh

`monitor.sh` enriches specs (via `run_spec_phase`) before launching workers. **Do not** add `run_spec_phase` calls to `feature.sh` or other entry points — that creates duplicate enrichment. The single canonical enrichment point is `monitor.sh` line ~248.

Exception: `bootstrap.sh` runs `run_all_phases` for the initial `multiclaude new` flow, and monitor.sh may re-run enrichment after — that's fine, the second run is a no-op on already-enriched specs.

### Keep subcommands minimal

Don't add aliases for subcommands (e.g. don't do `update|self-update|upgrade`). One name per command.

### Style

- Bash with `set -e`
- Colors via ANSI escape variables (`RED`, `GREEN`, `CYAN`, `YELLOW`, `NC`, `BOLD`, `DIM`)
- Logging helpers: `log_info`, `log_success`, `log_verbose`
- Commit messages: lowercase, imperative, concise

## Common flows

- `multiclaude new <name>` — bootstrap.sh creates project, runs all phases, starts dev session
- `multiclaude add --from-file <brief>` — feature.sh creates spec, monitor.sh enriches it before workers launch
- `multiclaude add <name>` + `multiclaude run` — interactive: feature.sh creates spec, monitor.sh enriches on run
- `multiclaude update` — self-update via remote install one-liner
