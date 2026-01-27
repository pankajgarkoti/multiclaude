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

    _phases_log "Research agent is working (this may take a few minutes)..."
    claude -p "$research_prompt" --dangerously-skip-permissions 2>&1 | while IFS= read -r line; do
        # Print a dot for each line of output to show activity
        printf "${CYAN}.${NC}" >&2
    done || true
    echo "" >&2  # newline after dots

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

## Inputs

1. **Research findings**: Read \`.multiclaude/research-findings.md\` (if it exists)
2. **Project specification**: Read \`.multiclaude/specs/PROJECT_SPEC.md\` (if it exists)
3. **Existing feature specs**: Read all files in \`.multiclaude/specs/features/\`
4. **Existing codebase**: Explore the project files to understand the actual code structure

## Existing specs to enrich:
${existing_specs}

## Your Tasks

For EACH feature spec in \`.multiclaude/specs/features/\`:

1. **Read the codebase** - understand project structure, existing files, tech stack
2. **Enrich the spec** with:
   - Concrete file paths that exist or should be created (based on actual project structure)
   - Real interfaces/types from the codebase (not hypothetical TypeScript if the project is Python)
   - Specific acceptance criteria (not placeholder TODOs)
   - Dependencies on other features or external packages
   - Testing approach appropriate for the actual tech stack
3. **Preserve** any existing content that is already concrete/specific
4. **Replace** placeholder content (TODO, template comments, hypothetical examples)

If no feature specs exist yet AND a PROJECT_SPEC.md exists:
1. Read the PROJECT_SPEC and research findings
2. Break the project into 3-7 independent feature modules
3. Create \`.multiclaude/specs/features/<name>.spec.md\` for each
4. Create \`.multiclaude/specs/.features\` with one feature name per line

## Guidelines
- Match the actual tech stack (don't assume TypeScript/Node.js)
- File paths should reflect real project structure
- Acceptance criteria should be testable and specific
- Each spec should be self-contained enough for an independent worker

When done, output: SPECS_ENRICHED
PROMPT_EOF

    _phases_log "Spec enrichment agent is working (this may take a few minutes)..."
    claude -p "$spec_prompt" --dangerously-skip-permissions 2>&1 | while IFS= read -r line; do
        printf "${CYAN}.${NC}" >&2
    done || true
    echo "" >&2

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

## Step 1: Understand the Project

Read these files (if they exist):
- `.multiclaude/specs/PROJECT_SPEC.md` - project purpose, goals, features
- `.multiclaude/research-findings.md` - industry patterns and best practices

## Step 2: Detect the Tech Stack

Inspect the project root for config files to determine the ACTUAL tech stack:
- `package.json` → Node.js/JavaScript/TypeScript (check for `typescript` dep)
- `Cargo.toml` → Rust
- `requirements.txt` / `pyproject.toml` / `setup.py` → Python
- `go.mod` → Go
- `Gemfile` → Ruby
- `pom.xml` / `build.gradle` → Java/Kotlin
- `Makefile`, `CMakeLists.txt` → C/C++
- Check for framework-specific files: `next.config.*`, `vite.config.*`, `angular.json`, etc.

If NO config files exist yet (greenfield project), infer the likely stack from
PROJECT_SPEC.md and research findings, and note that in the standards.

## Step 3: Generate Standards

Create `.multiclaude/specs/STANDARDS.md` following this format:

```markdown
# Project Quality Standards

This document defines quality standards the QA Agent will verify.
Standards are derived from research into similar products and project requirements.

## Detected Tech Stack
[List what you found: language, framework, test runner, linter, etc.]

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

    _phases_log "Standards agent is working (this may take a few minutes)..."
    claude -p "$standards_prompt" --dangerously-skip-permissions 2>&1 | while IFS= read -r line; do
        printf "${CYAN}.${NC}" >&2
    done || true
    echo "" >&2

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
