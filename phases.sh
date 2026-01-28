#!/bin/bash
#===============================================================================
# PHASES.SH - Shared research/planning/standards phases library
#
# Provides reusable phase functions that run `claude -p` instances which
# auto-exit without user input. Used by bootstrap.sh, feature.sh, and monitor.sh.
#===============================================================================

PHASES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors (safe to re-declare; no-ops if already set)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

_phases_log() {
    echo -e "${BLUE}[phases]${NC} $1"
}

_phases_ok() {
    echo -e "${GREEN}[phases]${NC} $1"
}

_phases_warn() {
    echo -e "${YELLOW}[phases]${NC} $1"
}

DIM='\033[2m'

# Run a claude -p command in the background with a spinner showing live actions.
# Injects --output-format stream-json --verbose into the claude command to parse
# tool calls and text output in real time, displaying them on a status line.
_phases_run_with_spinner() {
    local label="$1"
    shift

    local output_file status_file
    output_file=$(mktemp)
    status_file=$(mktemp)
    local _spinner_interrupted=false

    # Inject streaming flags into the claude command so we get JSON events
    local cmd=("$@")
    local stream_cmd=()
    for arg in "${cmd[@]}"; do
        stream_cmd+=("$arg")
    done
    stream_cmd+=(--output-format stream-json --verbose)

    # Run claude in background, stream JSON events to file
    "${stream_cmd[@]}" > "$output_file" 2>/dev/null &
    local pid=$!

    # Background parser: read JSON stream and extract status updates
    (
        tail -f "$output_file" 2>/dev/null | while IFS= read -r line; do
            # Skip empty lines
            [[ -z "$line" ]] && continue
            # Extract tool_use name -> "Using <ToolName>"
            local tool_name
            tool_name=$(echo "$line" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"//')
            if [[ -n "$tool_name" ]]; then
                # Try to get a description or command for Bash/Read/Edit tools
                local extra=""
                case "$tool_name" in
                    Bash)
                        extra=$(echo "$line" | grep -o '"description":"[^"]*"' | head -1 | sed 's/"description":"//;s/"$//')
                        [[ -z "$extra" ]] && extra=$(echo "$line" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//' | cut -c1-50)
                        ;;
                    Read|Edit|Write|Glob|Grep)
                        extra=$(echo "$line" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"$//')
                        [[ -z "$extra" ]] && extra=$(echo "$line" | grep -o '"pattern":"[^"]*"' | head -1 | sed 's/"pattern":"//;s/"$//')
                        ;;
                    WebSearch|WebFetch)
                        extra=$(echo "$line" | grep -o '"query":"[^"]*"' | head -1 | sed 's/"query":"//;s/"$//')
                        [[ -z "$extra" ]] && extra=$(echo "$line" | grep -o '"url":"[^"]*"' | head -1 | sed 's/"url":"//;s/"$//')
                        ;;
                esac
                if [[ -n "$extra" ]]; then
                    echo "${tool_name}: ${extra}" | cut -c1-72 > "$status_file"
                else
                    echo "Using ${tool_name}" > "$status_file"
                fi
                continue
            fi
            # Extract text content snippets from assistant messages
            local text
            text=$(echo "$line" | grep -o '"text":"[^"]*"' | head -1 | sed 's/"text":"//;s/"$//')
            if [[ -n "$text" && ${#text} -gt 10 ]]; then
                echo "$text" | cut -c1-72 > "$status_file"
            fi
        done
    ) &
    local parser_pid=$!

    # Ctrl+C should kill the child and abort, not skip
    trap '_spinner_interrupted=true; kill "$pid" "$parser_pid" 2>/dev/null; wait "$pid" "$parser_pid" 2>/dev/null' INT

    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local start=$SECONDS
    local last_detail=""
    # Print initial spinner + blank detail line
    printf "\n" >&2
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start ))
        local detail=""
        [[ -s "$status_file" ]] && detail=$(cat "$status_file" 2>/dev/null)
        [[ -n "$detail" ]] && last_detail="$detail"

        # Truncate content to terminal width to prevent line wrapping
        local max_label=$(( cols - 10 ))  # room for spinner char + elapsed + padding
        local max_detail=$(( cols - 6 ))  # room for "  ↳ " prefix
        local trunc_detail="${last_detail:-starting...}"
        [[ ${#trunc_detail} -gt $max_detail ]] && trunc_detail="${trunc_detail:0:$max_detail}"
        # Move up 1 line, clear it, print spinner, move down, clear, print detail
        printf "\033[1A\033[2K  ${CYAN}%s${NC} %s ${DIM}(%ds)${NC}\n\033[2K  ${DIM}↳ %s${NC}" \
            "${spin:i++%${#spin}:1}" "${label:0:$max_label}" "$elapsed" "$trunc_detail" >&2
        sleep 0.15
    done
    wait "$pid" || true
    kill "$parser_pid" 2>/dev/null; wait "$parser_pid" 2>/dev/null || true
    # Clear both lines
    printf "\033[1A\033[2K\033[1B\033[2K\033[1A" >&2
    rm -f "$output_file" "$status_file"

    # Restore default INT handler and re-raise if we were interrupted
    trap - INT
    if $_spinner_interrupted; then
        echo "" >&2
        _phases_warn "Interrupted by user"
        kill -INT $$
    fi
}

#-------------------------------------------------------------------------------
# run_research_phase <project_dir> <context>
#
# Runs a `claude -p` instance that researches similar products and creates
# .multiclaude/research-findings.md.  Auto-exits, no user input.
#
# Arguments:
#   project_dir - absolute path to the project root
#   context     - project description (for new) or feature brief (for add)
#-------------------------------------------------------------------------------
run_research_phase() {
    local project_dir="$1"
    local context="$2"

    _phases_log "Running research phase..."

    cd "$project_dir"
    mkdir -p "$project_dir/.multiclaude"

    local research_prompt
    read -r -d '' research_prompt << 'PROMPT_EOF' || true
You are a RESEARCH AGENT. Gather insights to inform project specifications and quality standards.

## Project Context
PROJECT_CONTEXT_PLACEHOLDER

## Tasks

1. **Analyze** the project description above. Extract URLs, product references, or domain terms.

2. **Browse referenced URLs** (if any) using web tools. Capture features, UI patterns, UX flows.

3. **Research 2-3 similar products** in this domain:
   - Search for similar products
   - For each, document: features, UI patterns, UX patterns, quality aspects

4. **Create** `.multiclaude/research-findings.md` with this structure:

```markdown
# Research Findings

## Project Context
[Brief summary of what we are building]

## Referenced URLs Analysis
### [URL 1]
- Key features: ...
- UI patterns: ...
- UX patterns: ...

## Similar Products Analyzed

### [Product 1]
- URL: ...
- Features: ...
- UI patterns: ...
- UX patterns: ...
- Quality aspects: ...

### [Product 2]
(same structure)

## UI/UX Recommendations
- [pattern]: [why recommended]

## Recommended Standards
- [standard]: [rationale]

## Industry Best Practices
- ...

## Technology Observations
- ...
```

5. When done, output: RESEARCH_COMPLETE
PROMPT_EOF

    # Inject the actual context
    research_prompt="${research_prompt//PROJECT_CONTEXT_PLACEHOLDER/$context}"

    _phases_run_with_spinner "Research agent working..." claude -p "$research_prompt" --dangerously-skip-permissions

    if [[ ! -f "$project_dir/.multiclaude/research-findings.md" ]]; then
        _phases_warn "Research phase did not produce findings; creating placeholder."
        cat > "$project_dir/.multiclaude/research-findings.md" << 'EOF'
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

    _phases_ok "Research phase complete."
}

#-------------------------------------------------------------------------------
# run_spec_phase <project_dir> [context]
#
# Runs `claude -p` to create/enrich feature specs in
# .multiclaude/specs/features/.  For existing projects it reads the codebase and
# enriches specs with concrete file paths, interfaces, and acceptance criteria.
#
# Arguments:
#   project_dir - absolute path to the project root
#   context     - (optional) project description for new projects
#-------------------------------------------------------------------------------
run_spec_phase() {
    local project_dir="$1"
    local context="${2:-}"

    _phases_log "Running spec enrichment phase..."

    cd "$project_dir"
    mkdir -p "$project_dir/.multiclaude/specs/features"

    # Build the list of existing specs for the prompt
    local existing_specs=""
    if ls "$project_dir/.multiclaude/specs/features"/*.spec.md &>/dev/null; then
        for spec in "$project_dir/.multiclaude/specs/features"/*.spec.md; do
            existing_specs="$existing_specs- $(basename "$spec")\n"
        done
    fi

    local context_section=""
    if [[ -n "$context" ]]; then
        context_section="## Project Description
$context"
    fi

    local spec_prompt
    read -r -d '' spec_prompt << PROMPT_EOF || true
You are a SPEC ENRICHMENT AGENT. Your job is to enrich feature specifications with concrete implementation details.

${context_section}

## ╔══════════════════════════════════════════════════════════════════════════════╗
## ║  STEP 1: EXTRACT TECH STACK (MANDATORY - DO THIS FIRST)                     ║
## ╚══════════════════════════════════════════════════════════════════════════════╝

Before writing ANY feature spec, you MUST:

1. Read \`.multiclaude/specs/PROJECT_SPEC.md\`
2. Find the tech stack (look for "Technology Stack", "Tech Stack", "Technologies")
3. Create \`.multiclaude/specs/TECHSTACK.md\` with the EXACT technologies specified

**TECHSTACK.md format:**
\`\`\`markdown
# Project Tech Stack

> **AUTHORITATIVE SOURCE** - All specs and code MUST use only these technologies.
> **Workers/QA**: Copy commands from this file verbatim. Do not improvise.

## Language
- Python 3.11+

## Frameworks
- FastAPI (web framework)
- Pydantic (validation)

## Testing
- pytest

## Package Manager
- uv

---

## Commands

**Copy these exactly when you need to run them.**

### Install Dependencies
\\\`\\\`\\\`bash
uv sync
\\\`\\\`\\\`

### Run Dev Server
\\\`\\\`\\\`bash
uvicorn src.server.main:app --reload --host 127.0.0.1 --port 8080
\\\`\\\`\\\`

### Run Tests
\\\`\\\`\\\`bash
pytest tests/ -v
\\\`\\\`\\\`

### Type Check (if applicable)
\\\`\\\`\\\`bash
mypy src/
\\\`\\\`\\\`

### Lint (if applicable)
\\\`\\\`\\\`bash
ruff check src/
\\\`\\\`\\\`
\`\`\`

**RULES:**
- Copy EXACTLY what PROJECT_SPEC.md says - do NOT substitute technologies
- Include ACTUAL RUNNABLE COMMANDS - not placeholders like "\$PKG_MGR install"
- Derive commands from the project's actual config (pyproject.toml, package.json, Cargo.toml)
- If the project has a README with commands, use those
- If no tech stack section exists, infer from config files and write concrete commands

## ╔══════════════════════════════════════════════════════════════════════════════╗
## ║  STEP 2: ENFORCE TECH STACK IN ALL SPECS                                    ║
## ╚══════════════════════════════════════════════════════════════════════════════╝

Every feature spec MUST match TECHSTACK.md:
- Language: Use Python if TECHSTACK says Python (NOT TypeScript)
- Framework: Use FastAPI if TECHSTACK says FastAPI (NOT Express)
- File extensions: .py for Python, .ts for TypeScript
- Imports: from fastapi import... (NOT import express)
- Tests: pytest (NOT Jest)

**If a spec uses wrong tech stack → REWRITE IT COMPLETELY**

## Inputs

1. Read \`.multiclaude/specs/PROJECT_SPEC.md\` - extract tech stack FIRST
2. Create \`.multiclaude/specs/TECHSTACK.md\` - before anything else
3. Read \`.multiclaude/research-findings.md\` (if exists)
4. Read \`.multiclaude/specs/features/\` - check each for tech stack compliance
5. Explore codebase to confirm tech stack

## Existing specs to enrich:
${existing_specs}

## Your Tasks

1. **Create TECHSTACK.md** from PROJECT_SPEC.md (mandatory first step)
2. **For each feature spec:**
   - Check: Does it match TECHSTACK.md?
   - If NO: Rewrite the entire spec using correct tech stack
   - If YES: Enrich with concrete paths, interfaces, acceptance criteria
3. **Create new specs** if none exist (all must use TECHSTACK.md)
4. **Create .features file** listing all feature names

## Final Verification

Before outputting SPECS_ENRICHED:
- [ ] TECHSTACK.md exists and matches PROJECT_SPEC.md
- [ ] All specs use the language from TECHSTACK.md
- [ ] All code blocks use correct syntax
- [ ] All file paths use correct extensions
- [ ] All imports are from correct ecosystem

When done, output: SPECS_ENRICHED
PROMPT_EOF

    _phases_run_with_spinner "Spec enrichment agent working..." claude -p "$spec_prompt" --dangerously-skip-permissions

    # Auto-detect features file if not created
    if [[ ! -f "$project_dir/.multiclaude/specs/.features" ]]; then
        if ls "$project_dir/.multiclaude/specs/features"/*.spec.md &>/dev/null; then
            for spec in "$project_dir/.multiclaude/specs/features"/*.spec.md; do
                basename "$spec" .spec.md
            done > "$project_dir/.multiclaude/specs/.features"
        fi
    fi

    _phases_ok "Spec enrichment phase complete."
}

#-------------------------------------------------------------------------------
# run_standards_phase <project_dir>
#
# Generates .multiclaude/specs/STANDARDS.md from research findings + project
# spec.  The prompt is project-aware: it reads config files to detect the
# actual tech stack and generates standards relevant to this specific project.
#-------------------------------------------------------------------------------
run_standards_phase() {
    local project_dir="$1"

    _phases_log "Running standards generation phase..."

    cd "$project_dir"

    local standards_prompt
    read -r -d '' standards_prompt << 'PROMPT_EOF' || true
You are a STANDARDS GENERATION AGENT. Generate project-specific quality standards.

## Step 1: Read the Tech Stack

**CRITICAL**: Read `.multiclaude/specs/TECHSTACK.md` first. This is the authoritative source.
Do NOT re-detect or guess the tech stack — use what TECHSTACK.md says.

If TECHSTACK.md doesn't exist, read `.multiclaude/specs/PROJECT_SPEC.md` and extract it.

## Step 2: Understand the Project

Read these files:
- `.multiclaude/specs/TECHSTACK.md` - **authoritative tech stack** (use this!)
- `.multiclaude/specs/PROJECT_SPEC.md` - project purpose, goals, features
- `.multiclaude/research-findings.md` - industry patterns and best practices

## Step 3: Generate Standards

Create `.multiclaude/specs/STANDARDS.md` following this format:

```markdown
# Project Quality Standards

This document defines quality standards the QA Agent will verify.
Standards are derived from research into similar products and project requirements.

## Tech Stack (from TECHSTACK.md)
[Copy the tech stack from TECHSTACK.md - do not re-detect]

## Testing Standards

### STD-T001: [Name]
**Category**: Testing

As a [user/developer], [user story].

**Verification**: [Specific command for THIS project's tech stack]
**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2
```

## Rules for Standard Generation

1. **Verification commands must match the actual tech stack:**
   - Python project → `pytest`, `python -m unittest`, NOT `npm test`
   - Rust project → `cargo test`, NOT `npm test`
   - Go project → `go test ./...`
   - Node.js project → check package.json scripts for the actual test command
   - If no test runner is configured, say "Configure and run the project's test suite"

2. **Only include relevant categories:**
   - UI standards → only if the project has a user interface
   - API standards → only if it exposes an API
   - Security standards → always include basics, extend for auth-heavy projects
   - Performance standards → tailor to project type (web app vs CLI vs library)

3. **Functional standards must come from the actual PROJECT_SPEC features**
   - Read the feature list and create standards that verify those features work
   - Don't invent features that aren't in the spec

4. **Include 15-25 total standards** covering:
   - Testing (STD-T): appropriate for the detected test framework
   - Security (STD-S): no hardcoded secrets, input validation, auth if applicable
   - Code Quality (STD-Q): linting/formatting for the actual language
   - Functional (STD-F): derived from PROJECT_SPEC features
   - UI (STD-U): only if it's a UI project
   - Performance (STD-P): appropriate for the project type

When done, output: STANDARDS_COMPLETE
PROMPT_EOF

    _phases_run_with_spinner "Standards agent working..." claude -p "$standards_prompt" --dangerously-skip-permissions

    if [[ ! -f "$project_dir/.multiclaude/specs/STANDARDS.md" ]]; then
        _phases_warn "Standards generation did not produce output; creating generic fallback."
        cat > "$project_dir/.multiclaude/specs/STANDARDS.md" << 'EOF'
# Project Quality Standards

This document defines quality standards the QA Agent will verify.

## Detected Tech Stack
Unable to detect automatically. Standards below are generic.

## Testing Standards

### STD-T001: Tests Pass
**Category**: Testing

As a developer, all project tests should pass before merging.

**Verification**: Run the project's configured test command
**Acceptance Criteria**:
- [ ] All tests pass
- [ ] No skipped tests without justification

## Security Standards

### STD-S001: No Hardcoded Secrets
**Category**: Security

As a developer, no sensitive data should be in source code.

**Verification**: Search source files for password, secret, api_key patterns
**Acceptance Criteria**:
- [ ] No API keys in source code
- [ ] No passwords in source code
- [ ] Secrets use environment variables

## Code Quality Standards

### STD-Q001: No Lint Errors
**Category**: CodeQuality

As a developer, code should follow the project's style guidelines.

**Verification**: Run the project's configured lint command
**Acceptance Criteria**:
- [ ] Linter passes with no errors
- [ ] No warnings without documented exceptions
EOF
    fi

    _phases_ok "Standards generation phase complete."
}

#-------------------------------------------------------------------------------
# run_all_phases <project_dir> <context>
#
# Convenience: runs research -> spec -> standards in sequence.
# Creates SPECS_READY marker when all phases complete.
#-------------------------------------------------------------------------------
run_all_phases() {
    local project_dir="$1"
    local context="$2"

    _phases_log "Running all phases: research -> spec -> standards"

    run_research_phase "$project_dir" "$context"
    run_spec_phase "$project_dir" "$context"
    run_standards_phase "$project_dir"

    touch "$project_dir/.multiclaude/SPECS_READY"
    _phases_ok "All phases complete. SPECS_READY marker created."
}
