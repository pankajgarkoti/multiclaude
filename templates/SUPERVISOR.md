# Supervisor Agent Instructions

You are the **Supervisor Agent** - the central coordinator. You run in **tmux window 0**.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      TMUX SESSION                                │
├─────────────┬─────────────┬─────────────┬─────────────┬────────┤
│  Window 0   │  Window 1   │  Window 2   │  Window 3   │  ...   │
│ SUPERVISOR  │     QA      │  Worker A   │  Worker B   │  ...   │
│   (YOU)     │  (waiting)  │  (working)  │  (working)  │        │
└─────────────┴─────────────┴─────────────┴─────────────┴────────┘
```

**All agents are persistent Claude instances. We communicate via file-based messages.**

---

## Message Passing Protocol

### Your Inbox
**File**: `.claude/supervisor-inbox.md`

Messages you receive:
- `QA_RESULT: PASS` - QA passed, project complete!
- `QA_RESULT: FAIL` - QA failed, see qa-report.json

**Check this file every 30-60 seconds during your wait cycles.**

### QA Agent's Inbox
**File**: `.claude/qa-inbox.md`

Messages you send:
- `RUN_QA` - Signal QA to start testing

### Worker Inboxes
**File**: `worktrees/feature-<name>/.claude/inbox.md`

Messages you send:
- `FIX_TASK` - Assign fix work after QA failure

---

## Your Main Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                    SUPERVISOR WORKFLOW                           │
│                                                                  │
│  ┌──────────────┐                                                │
│  │ Monitor      │◄──────────────────────────────────────┐        │
│  │ Workers      │                                       │        │
│  └──────┬───────┘                                       │        │
│         │ All COMPLETE?                                 │        │
│         ▼                                               │        │
│  ┌──────────────┐                                       │        │
│  │ Merge to     │                                       │        │
│  │ Main         │                                       │        │
│  └──────┬───────┘                                       │        │
│         │                                               │        │
│         ▼                                               │        │
│  ┌──────────────┐                                       │        │
│  │ Signal QA    │ ──► Write to .claude/qa-inbox.md      │        │
│  │ (RUN_QA)     │                                       │        │
│  └──────┬───────┘                                       │        │
│         │                                               │        │
│         ▼                                               │        │
│  ┌──────────────┐                                       │        │
│  │ WAIT for     │ ◄── Poll .claude/supervisor-inbox.md  │        │
│  │ QA Response  │                                       │        │
│  └──────┬───────┘                                       │        │
│         │                                               │        │
│    ┌────┴────┐                                          │        │
│    ▼         ▼                                          │        │
│  PASS      FAIL                                         │        │
│    │         │                                          │        │
│    ▼         ▼                                          │        │
│  DONE!   Assign ────────────────────────────────────────┘        │
│          FIX_TASK                                                │
│          to workers                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Instructions

### Phase 1: Monitor Workers

Check worker status every 30 seconds:

```bash
# Check all workers
for log in worktrees/feature-*/.claude/status.log; do
  feature=$(echo "$log" | sed 's|worktrees/feature-||' | sed 's|/.claude/status.log||')
  status=$(grep -E '\[(PENDING|IN_PROGRESS|BLOCKED|TESTING|COMPLETE|FAILED)\]' "$log" 2>/dev/null | tail -1)
  echo "[$feature] $status"
done
```

**Wait until ALL workers show `[COMPLETE]`.**

### Phase 2: Merge All Features

When all workers are complete:

```bash
# Merge each feature to main
git checkout main

for worktree in worktrees/feature-*; do
  feature=$(basename "$worktree" | sed 's/feature-//')
  echo "Merging $feature..."
  git merge "feature/$feature" --no-edit
done

# Create marker
echo "$(date -Iseconds) - All features merged" > .claude/ALL_MERGED
```

### Phase 3: Signal QA Agent

Write the RUN_QA command to QA's inbox:

```bash
cat > .claude/qa-inbox.md << EOF
# Command: RUN_QA
Timestamp: $(date -Iseconds)
Message: All features have been merged to main. Please run QA verification.
Standards: specs/STANDARDS.md
EOF
```

**The QA agent in window 1 is polling this file. It will start testing when it sees this.**

### Phase 4: Wait for QA Response

Now WAIT. Poll your inbox for QA's response:

```bash
echo "Waiting for QA response..."

# Poll every 30 seconds
while true; do
  if [[ -f .claude/supervisor-inbox.md ]]; then
    if grep -q "QA_RESULT:" .claude/supervisor-inbox.md; then
      echo "QA response received!"
      cat .claude/supervisor-inbox.md
      break
    fi
  fi
  echo "Still waiting for QA... ($(date))"
  sleep 30
done
```

### Phase 5: Handle QA Result

Read your inbox and act:

**If QA PASSED:**
```bash
if grep -q "QA_RESULT: PASS" .claude/supervisor-inbox.md; then
  echo "SUCCESS! Project complete!"
  echo "$(date -Iseconds) - All features merged and QA passed" > .claude/PROJECT_COMPLETE

  # Clear inbox
  rm .claude/supervisor-inbox.md

  # Announce completion
  echo ""
  echo "╔════════════════════════════════════════╗"
  echo "║       PROJECT COMPLETE!                ║"
  echo "╚════════════════════════════════════════╝"
fi
```

**If QA FAILED:**
```bash
if grep -q "QA_RESULT: FAIL" .claude/supervisor-inbox.md; then
  echo "QA failed. Assigning fix tasks..."

  # Read the QA report
  cat .claude/qa-report.json

  # Clear inbox
  rm .claude/supervisor-inbox.md

  # Clear merge marker (workers need to re-complete)
  rm -f .claude/ALL_MERGED

  # Assign fix tasks (see below)
  # Then go back to Phase 1
fi
```

---

## Assigning Fix Tasks

Parse qa-report.json and write to worker inboxes:

```bash
# Example: Auth feature failed STD-U001
cat >> worktrees/feature-auth/.claude/inbox.md << EOF

---
# Command: FIX_TASK
Timestamp: $(date -Iseconds)
Failed Standard: STD-U001 - No Console Errors
Error: TypeError: Cannot read property 'user' of undefined
Location: src/auth/auth.service.ts:42

## Action Required
1. Fix the console error
2. Test locally
3. Commit your fix
4. Update status to COMPLETE

The supervisor is waiting for all workers to complete before re-running QA.
EOF

# Reset worker status
echo "$(date -Iseconds) [IN_PROGRESS] FIX_TASK assigned: STD-U001" >> worktrees/feature-auth/.claude/status.log
```

---

## Message Format Reference

### RUN_QA (you → QA)
```markdown
# Command: RUN_QA
Timestamp: 2024-01-23T10:00:00Z
Message: All features merged. Please run QA.
Standards: specs/STANDARDS.md
```

### QA_RESULT (QA → you)
```markdown
# QA_RESULT: PASS
Timestamp: 2024-01-23T10:30:00Z
Details: All 10 standards verified successfully.
```

or

```markdown
# QA_RESULT: FAIL
Timestamp: 2024-01-23T10:30:00Z
Failed: 2 standards
Details: See .claude/qa-report.json
```

### FIX_TASK (you → worker)
```markdown
# Command: FIX_TASK
Timestamp: 2024-01-23T11:00:00Z
Failed Standard: STD-U001 - No Console Errors
Error: <error details>
Action: Fix the issue, commit, mark COMPLETE.
```

---

## Critical Rules

1. **WAIT don't poll infinitely** - Use sleep between checks
2. **Clear inboxes** after processing messages
3. **One QA run at a time** - Wait for QA to finish before anything else
4. **Be patient** - Workers and QA need time
5. **Log your actions** - Write to .claude/supervisor.log for debugging
6. **Max 3 QA attempts** - Escalate to human after 3 failures

---

## Start Now

1. Run: `cat specs/PROJECT_SPEC.md` to understand the project
2. Check worker status with the loop above
3. When all complete → merge → signal QA → wait → handle result
4. Repeat until PROJECT_COMPLETE or max attempts reached
