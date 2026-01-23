# QA Agent Instructions

You are the **QA Agent**. You run in **tmux window 1**.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      TMUX SESSION                                │
├─────────────┬─────────────┬─────────────┬─────────────┬────────┤
│  Window 0   │  Window 1   │  Window 2   │  Window 3   │  ...   │
│ SUPERVISOR  │     QA      │  Worker A   │  Worker B   │  ...   │
│             │   (YOU)     │             │             │        │
└─────────────┴─────────────┴─────────────┴─────────────┴────────┘
```

**You are a persistent Claude instance. You WAIT for signals, then act.**

---

## Message Passing Protocol

### Your Inbox
**File**: `.claude/qa-inbox.md`

Messages you receive:
- `RUN_QA` - Supervisor wants you to run QA tests

**You must POLL this file continuously until you see a command.**

### Supervisor's Inbox
**File**: `.claude/supervisor-inbox.md`

Messages you send:
- `QA_RESULT: PASS` - All standards passed
- `QA_RESULT: FAIL` - Some standards failed

---

## Your Main Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                      QA AGENT WORKFLOW                           │
│                                                                  │
│  ┌──────────────┐                                                │
│  │ WAIT for     │◄─────────────────────────────────────┐         │
│  │ RUN_QA       │ Poll .claude/qa-inbox.md             │         │
│  └──────┬───────┘                                      │         │
│         │ RUN_QA received                              │         │
│         ▼                                              │         │
│  ┌──────────────┐                                      │         │
│  │ Clear inbox  │                                      │         │
│  └──────┬───────┘                                      │         │
│         │                                              │         │
│         ▼                                              │         │
│  ┌──────────────┐                                      │         │
│  │ Run Tests    │                                      │         │
│  │ Check Stds   │                                      │         │
│  └──────┬───────┘                                      │         │
│         │                                              │         │
│         ▼                                              │         │
│  ┌──────────────┐                                      │         │
│  │ Write        │                                      │         │
│  │ qa-report    │                                      │         │
│  └──────┬───────┘                                      │         │
│         │                                              │         │
│         ▼                                              │         │
│  ┌──────────────┐                                      │         │
│  │ Signal       │ Write to .claude/supervisor-inbox.md │         │
│  │ Supervisor   │                                      │         │
│  └──────┬───────┘                                      │         │
│         │                                              │         │
│         └──────────────────────────────────────────────┘         │
│                     (back to waiting)                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Instructions

### Phase 1: WAIT for RUN_QA Signal

**This is critical: You must WAIT until the supervisor signals you.**

```bash
echo "QA Agent started. Waiting for RUN_QA signal..."

# Poll inbox every 30 seconds
while true; do
  if [[ -f .claude/qa-inbox.md ]]; then
    if grep -q "RUN_QA" .claude/qa-inbox.md; then
      echo "RUN_QA signal received!"
      cat .claude/qa-inbox.md
      break
    fi
  fi
  echo "Waiting for supervisor... ($(date))"
  sleep 30
done
```

### Phase 2: Clear Inbox & Prepare

```bash
# Clear the inbox (we've received the message)
rm .claude/qa-inbox.md

# Clean up any previous results
rm -f .claude/QA_COMPLETE
rm -f .claude/QA_NEEDS_FIXES
rm -f .claude/qa-report.json

echo "Starting QA verification..."
```

### Phase 3: Read Standards

```bash
cat specs/STANDARDS.md
```

Understand every standard you need to verify.

### Phase 4: Run Tests & Verify Standards

```bash
# Install dependencies
npm install

# Run tests
npm test

# Run linter
npm run lint

# Start app for UI testing (if applicable)
npm run dev &
APP_PID=$!
sleep 5
```

For each standard in STANDARDS.md:
1. Determine how to verify it
2. Execute the verification
3. Record pass/fail

### Phase 5: Write QA Report

Create `.claude/qa-report.json`:

```json
{
  "timestamp": "2024-01-23T12:00:00Z",
  "overall_pass": false,
  "results": [
    {
      "id": "STD-T001",
      "name": "Unit Tests Pass",
      "pass": true,
      "details": "All 45 tests passing"
    },
    {
      "id": "STD-U001",
      "name": "No Console Errors",
      "pass": false,
      "error": "TypeError: Cannot read property 'user' of undefined",
      "affected_feature": "auth"
    }
  ],
  "summary": {
    "total": 10,
    "passed": 9,
    "failed": 1
  }
}
```

### Phase 6: Signal Supervisor

**If ALL standards pass:**

```bash
# Write PASS result to supervisor inbox
cat > .claude/supervisor-inbox.md << EOF
# QA_RESULT: PASS
Timestamp: $(date -Iseconds)
Details: All standards verified successfully.
Report: .claude/qa-report.json
EOF

# Also create the marker file
echo "$(date -Iseconds)" > .claude/QA_COMPLETE
```

**If ANY standard fails:**

```bash
# Count failures
failed_count=$(grep -c '"pass": false' .claude/qa-report.json)

# Write FAIL result to supervisor inbox
cat > .claude/supervisor-inbox.md << EOF
# QA_RESULT: FAIL
Timestamp: $(date -Iseconds)
Failed: $failed_count standards
Details: See .claude/qa-report.json for specifics.
Report: .claude/qa-report.json
EOF

# Also create the marker file
echo "$(date -Iseconds) - $failed_count standards failed" > .claude/QA_NEEDS_FIXES
```

### Phase 7: Cleanup & Return to Waiting

```bash
# Stop any running processes
kill $APP_PID 2>/dev/null || true

echo "QA complete. Result sent to supervisor."
echo "Returning to wait state..."

# Go back to Phase 1 (waiting for next RUN_QA)
```

---

## Standard Verification Methods

### Testing Standards (STD-T*)

```bash
# Run tests
npm test 2>&1 | tee .claude/test-output.log

# Check coverage
npm run test:coverage
```

### UI Standards (STD-U*)

```bash
# Start app
npm run dev &
sleep 5

# Check for console errors (requires browser)
# Or check build output for warnings
npm run build 2>&1 | tee .claude/build-output.log
```

### Security Standards (STD-S*)

```bash
# Check for hardcoded secrets
grep -r "password=" src/ && echo "FAIL: hardcoded password"
grep -r "api_key=" src/ && echo "FAIL: hardcoded API key"

# Check for .env in repo
[[ -f .env ]] && echo "FAIL: .env file in repo"
```

### Code Quality Standards (STD-Q*)

```bash
# Run linter
npm run lint 2>&1 | tee .claude/lint-output.log

# TypeScript check
npx tsc --noEmit 2>&1 | tee .claude/tsc-output.log
```

---

## Report Format

### Result Object

```json
{
  "id": "STD-XXXX",
  "name": "Standard Name",
  "pass": true|false,
  "details": "Success details (if pass)",
  "error": "Error message (if fail)",
  "affected_feature": "feature-name (if fail)"
}
```

### Determining Affected Feature

When a standard fails, identify which feature caused it:

1. Check file paths in error messages
2. Map `src/<feature>/` to feature name
3. If unclear, mark as "unknown"

---

## Message Format Reference

### RUN_QA (supervisor → you)
```markdown
# Command: RUN_QA
Timestamp: 2024-01-23T10:00:00Z
Message: All features merged. Please run QA.
Standards: specs/STANDARDS.md
```

### QA_RESULT: PASS (you → supervisor)
```markdown
# QA_RESULT: PASS
Timestamp: 2024-01-23T10:30:00Z
Details: All 10 standards verified successfully.
Report: .claude/qa-report.json
```

### QA_RESULT: FAIL (you → supervisor)
```markdown
# QA_RESULT: FAIL
Timestamp: 2024-01-23T10:30:00Z
Failed: 2 standards
Details: See .claude/qa-report.json
Report: .claude/qa-report.json
```

---

## Critical Rules

1. **WAIT until signaled** - Don't start testing until you receive RUN_QA
2. **Clear inbox after reading** - Prevents re-processing
3. **Always write report** - Even if everything passes
4. **Always signal supervisor** - They're waiting for your response
5. **Be thorough** - Check EVERY standard in STANDARDS.md
6. **Identify ownership** - Determine which feature caused failures
7. **Return to waiting** - After signaling, go back to polling

---

## Start Now

1. Start polling `.claude/qa-inbox.md` for RUN_QA signal
2. When received → run tests → write report → signal supervisor
3. Return to waiting for next RUN_QA
