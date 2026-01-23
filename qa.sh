#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# QA AGENT LAUNCHER
# Launches a Claude instance to verify quality standards
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:-.}"
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_PATH")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

cd "$PROJECT_PATH"

printf "${CYAN}═══════════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}                    QA AGENT LAUNCHER${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════════════════${NC}\n"
echo ""
echo "Project: $PROJECT_NAME"
echo "Path:    $PROJECT_PATH"
echo ""

# Ensure .claude directory exists
mkdir -p "$PROJECT_PATH/.claude"

# Copy QA instructions from templates if not present
if [[ ! -f "$PROJECT_PATH/.claude/QA_INSTRUCTIONS.md" ]]; then
    if [[ -f "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" ]]; then
        cp "$SCRIPT_DIR/templates/QA_INSTRUCTIONS.md" "$PROJECT_PATH/.claude/QA_INSTRUCTIONS.md"
        printf "${GREEN}[OK]${NC} QA instructions installed\n"
    fi
fi

# Check for STANDARDS.md
if [[ ! -f "$PROJECT_PATH/specs/STANDARDS.md" ]]; then
    printf "${RED}[ERROR]${NC} specs/STANDARDS.md not found\n"
    echo "The QA agent needs quality standards to verify against."

    # Check if template exists
    if [[ -f "$SCRIPT_DIR/templates/STANDARDS.template.md" ]]; then
        echo ""
        read -p "Create STANDARDS.md from template? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            mkdir -p "$PROJECT_PATH/specs"
            cp "$SCRIPT_DIR/templates/STANDARDS.template.md" "$PROJECT_PATH/specs/STANDARDS.md"
            printf "${GREEN}[OK]${NC} Created specs/STANDARDS.md from template\n"
            echo "Please review and customize the standards for your project."
        else
            exit 1
        fi
    else
        exit 1
    fi
fi

printf "${GREEN}[OK]${NC} Found specs/STANDARDS.md\n"

# Clean up any previous QA results
rm -f "$PROJECT_PATH/.claude/QA_COMPLETE"
rm -f "$PROJECT_PATH/.claude/QA_NEEDS_FIXES"
rm -f "$PROJECT_PATH/.claude/qa-report.json"

echo ""

# Count standards
standard_count=$(grep -c "^### STD-" "$PROJECT_PATH/specs/STANDARDS.md" 2>/dev/null || echo "0")
printf "${BOLD}Standards to verify:${NC} $standard_count\n"
echo ""

# Build the QA prompt
QA_PROMPT=$(cat << 'PROMPT_EOF'
You are the QA Agent for this project. Your job is to verify all quality standards.

## Immediate Actions

1. Read your instructions at `.claude/QA_INSTRUCTIONS.md` (if exists)
2. Read all standards at `specs/STANDARDS.md`
3. Begin verification

## Your Mission

Test every standard in STANDARDS.md and produce a report:

1. **Start the application** (if applicable)
2. **Run the test suite**
3. **Verify each standard** one by one
4. **Write qa-report.json** with detailed results
5. **Create result file**:
   - `.claude/QA_COMPLETE` if ALL standards pass
   - `.claude/QA_NEEDS_FIXES` if ANY standard fails

## QA Report Format

Write `.claude/qa-report.json`:

```json
{
  "timestamp": "ISO-8601",
  "overall_pass": true|false,
  "results": [
    {
      "id": "STD-T001",
      "name": "Standard Name",
      "pass": true|false,
      "details": "Success details or error message",
      "affected_feature": "feature-name if failed"
    }
  ]
}
```

## Important

- Test EVERY standard in STANDARDS.md
- Be thorough and specific in your report
- Identify which feature caused any failures
- Always create either QA_COMPLETE or QA_NEEDS_FIXES when done

Start by reading specs/STANDARDS.md.
PROMPT_EOF
)

printf "${BOLD}Launching QA Agent...${NC}\n"
echo ""
printf "${YELLOW}The QA agent will:${NC}\n"
echo "  1. Read all quality standards"
echo "  2. Start the application"
echo "  3. Run tests and verify each standard"
echo "  4. Write qa-report.json with results"
echo "  5. Create QA_COMPLETE or QA_NEEDS_FIXES"
echo ""
printf "${CYAN}─────────────────────────────────────────${NC}\n"
echo ""

# Check if --chrome flag should be used
USE_CHROME=""
if [[ "${QA_USE_CHROME:-}" == "true" ]] || [[ "$*" == *"--chrome"* ]]; then
    USE_CHROME="--chrome"
    echo "Browser access enabled (--chrome)"
    echo ""
fi

# Launch Claude with -p flag (auto-exits after completion)
# Use || true to prevent script exit on Claude error
set +e
if [[ -n "$USE_CHROME" ]]; then
    claude $USE_CHROME --dangerously-skip-permissions -p "$QA_PROMPT"
    CLAUDE_EXIT=$?
else
    claude --dangerously-skip-permissions -p "$QA_PROMPT"
    CLAUDE_EXIT=$?
fi
set -e

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    printf "${YELLOW}[WARN]${NC} Claude exited with code $CLAUDE_EXIT\n"
    echo ""
fi

# Report result
echo ""
printf "${CYAN}─────────────────────────────────────────${NC}\n"
echo ""

if [[ -f "$PROJECT_PATH/.claude/QA_COMPLETE" ]]; then
    printf "${GREEN}╔════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║           QA PASSED                    ║${NC}\n"
    printf "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    echo ""
    echo "All quality standards have been verified."
    exit 0
elif [[ -f "$PROJECT_PATH/.claude/QA_NEEDS_FIXES" ]]; then
    printf "${RED}╔════════════════════════════════════════╗${NC}\n"
    printf "${RED}║         QA NEEDS FIXES                 ║${NC}\n"
    printf "${RED}╚════════════════════════════════════════╝${NC}\n"
    echo ""
    if [[ -f "$PROJECT_PATH/.claude/qa-report.json" ]]; then
        echo "Failed standards:"
        # Try to parse and show failed standards
        grep -B2 '"pass": false' "$PROJECT_PATH/.claude/qa-report.json" 2>/dev/null | grep '"id"' | sed 's/.*"id": "\([^"]*\)".*/  - \1/' || true
        echo ""
        echo "See .claude/qa-report.json for details."
    fi
    exit 1
else
    printf "${YELLOW}[WARN]${NC} QA agent did not create a result file\n"
    echo "Check .claude/qa-report.json if it exists."
    exit 1
fi
