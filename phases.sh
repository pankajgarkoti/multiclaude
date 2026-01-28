#!/bin/bash
#===============================================================================
# PHASES.SH - Shared research/planning/standards phases library
#
# Provides reusable phase functions that run `claude -p` instances which
# auto-exit without user input. Used by bootstrap.sh, feature.sh, and monitor.sh.
#===============================================================================

PHASES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PHASES_SCRIPT_DIR/common.sh"

_phases_log() {
    echo -e "${BLUE}[phases]${NC} $1"
}

_phases_ok() {
    echo -e "${GREEN}[phases]${NC} $1"
}

_phases_warn() {
    echo -e "${YELLOW}[phases]${NC} $1"
}

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

    # Ctrl+C should kill the child, restore terminal, and abort
    trap '_spinner_interrupted=true; kill "$pid" "$parser_pid" 2>/dev/null; wait "$pid" "$parser_pid" 2>/dev/null; tput cnorm 2>/dev/null; stty echo icanon 2>/dev/null' INT

    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local start=$SECONDS
    local last_detail=""
    # Hide cursor and disable input echo during spinner
    tput civis 2>/dev/null
    local old_stty
    old_stty=$(stty -g 2>/dev/null)
    stty -echo -icanon 2>/dev/null
    # Print initial lines for spinner and detail
    printf "\n\n" >&2
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
        # Move up 1 line, clear it, go to col 0, print spinner, newline, clear, go to col 0, print detail
        printf "\033[1A\033[2K\033[G${CYAN}%s${NC} %s ${DIM}(%ds)${NC}\n\033[2K\033[G  ${DIM}↳ %s${NC}" \
            "${spin:i++%${#spin}:1}" "${label:0:$max_label}" "$elapsed" "$trunc_detail" >&2
        sleep 0.15
    done
    wait "$pid" || true
    kill "$parser_pid" 2>/dev/null; wait "$parser_pid" 2>/dev/null || true
    # Clear spinner and detail lines, move back up to where we started
    printf "\033[1A\033[2K\033[G\033[1B\033[2K\033[G\033[2A" >&2
    # Restore cursor and terminal settings
    tput cnorm 2>/dev/null
    [[ -n "$old_stty" ]] && stty "$old_stty" 2>/dev/null
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
You are a SPEC ENRICHMENT AGENT. Your job is to:
1. Extract and document the tech stack
2. Create the base project scaffold in the CORRECT language
3. Enrich feature specifications with concrete implementation details

${context_section}

## Step 1: Extract Tech Stack (do this first)

Before doing anything else:

1. Read \`.multiclaude/specs/PROJECT_SPEC.md\` and find the tech stack
2. Create \`.multiclaude/specs/TECHSTACK.md\` containing:
   - Language and version (e.g., Python 3.11+)
   - Frameworks (e.g., FastAPI, Pydantic)
   - Test framework (e.g., pytest)
   - Package manager (e.g., uv, pip, npm)
   - Actual runnable commands for: install, dev server, tests, lint
3. Derive commands from the project's config files (pyproject.toml, package.json, etc.)

**Critical**: Copy the tech stack from PROJECT_SPEC.md exactly. Do NOT substitute technologies.

## Step 2: Create Base Project Scaffold

After creating TECHSTACK.md, set up the base project structure using the CORRECT tech stack.

**Read PROJECT_SPEC.md for the directory structure.** Then create:

1. **Directory structure** as defined in PROJECT_SPEC.md
2. **Package config files** (if they don't exist):
   - Python: \`pyproject.toml\` with dependencies from PROJECT_SPEC.md
   - Node.js: \`package.json\` with dependencies
3. **Shared modules** in the correct language:
   - Python: \`src/shared/__init__.py\`, \`src/shared/types.py\` with base Pydantic models
   - TypeScript: \`src/shared/index.ts\`, \`src/shared/types.ts\` with interfaces
4. **Feature module stubs** for each feature:
   - Create the directory: \`src/<feature>/\`
   - Create \`__init__.py\` (Python) or \`index.ts\` (TypeScript)
   - Create a minimal service stub in the correct language
   - Create a test stub in the correct test framework
5. **Main entry point**:
   - Python: \`src/__init__.py\` or \`src/main.py\`
   - TypeScript: \`src/index.ts\`

**CRITICAL**:
- If PROJECT_SPEC.md says Python/FastAPI, create .py files with Python syntax
- If PROJECT_SPEC.md says TypeScript/Node, create .ts files with TypeScript syntax
- NEVER create TypeScript files for a Python project or vice versa

## Step 3: Enforce Tech Stack in All Specs

Every feature spec must use the technologies from TECHSTACK.md:
- Correct language and file extensions
- Correct framework imports
- Correct test framework

If any existing spec uses wrong technologies, rewrite it completely.

## Inputs

1. Read \`.multiclaude/specs/PROJECT_SPEC.md\` - extract tech stack and directory structure
2. Create \`.multiclaude/specs/TECHSTACK.md\` - before anything else
3. Read \`.multiclaude/research-findings.md\` (if exists)
4. Read \`.multiclaude/specs/features/\` - check each for tech stack compliance

## Existing specs to enrich:
${existing_specs}

## Your Tasks

1. **Create TECHSTACK.md** from PROJECT_SPEC.md (mandatory first step)
2. **Create base project scaffold** in the correct language (Step 2 above)
3. **For each feature spec:**
   - Check: Does it match TECHSTACK.md?
   - If NO: Rewrite the entire spec using correct tech stack
   - If YES: Enrich with concrete paths, interfaces, acceptance criteria
4. **Create new specs** if none exist (all must use TECHSTACK.md)
   - **IMPORTANT**: Feature spec files MUST be named \`<feature-name>.spec.md\`
   - Example: \`fastapi-server.spec.md\`, \`auth-system.spec.md\`
   - Do NOT use \`.md\` alone - always use \`.spec.md\` extension
5. **Create .features file** listing all feature names (one per line, without extension)
6. **Create README.md** for the project:
   - Describe what the project does (from PROJECT_SPEC.md overview)
   - List key features
   - Show the tech stack
   - Include setup/installation commands from TECHSTACK.md
   - Include development commands (run server, run tests, etc.)
   - This should be a proper project README, NOT a multiclaude workflow guide

## Final Verification

Before outputting SPECS_ENRICHED:
- [ ] TECHSTACK.md exists and matches PROJECT_SPEC.md
- [ ] Base scaffold uses the CORRECT language (Python .py files for Python projects!)
- [ ] All specs use the language from TECHSTACK.md
- [ ] All code blocks use correct syntax
- [ ] All file paths use correct extensions
- [ ] All imports are from correct ecosystem
- [ ] README.md describes the actual project (not multiclaude workflow)

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
