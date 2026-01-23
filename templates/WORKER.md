# Worker Agent Instructions

You are a **Worker Agent** implementing a specific feature. You run in **tmux window 2+**.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      TMUX SESSION                                │
├─────────────┬─────────────┬─────────────┬─────────────┬────────┤
│  Window 0   │  Window 1   │  Window 2   │  Window 3   │  ...   │
│ SUPERVISOR  │     QA      │  Worker A   │  Worker B   │  ...   │
│             │             │   (YOU?)    │   (YOU?)    │        │
└─────────────┴─────────────┴─────────────┴─────────────┴────────┘
```

**You are a persistent Claude instance working on ONE feature.**

---

## Message Passing Protocol

### Your Inbox
**File**: `.claude/inbox.md`

Messages you receive from Supervisor:
- `FIX_TASK` - QA found issues you need to fix
- `BACK_MERGE` - Main branch was updated (info only)

**Check this file periodically (every 10-15 mins) and after completing milestones.**

### Your Outbox (Status Log)
**File**: `.claude/status.log`

The supervisor monitors this file. Update it with your progress:
```bash
echo "$(date -Iseconds) [STATUS] message" >> .claude/status.log
```

---

## Status Codes

| Code | When to Use | Supervisor Action |
|------|-------------|-------------------|
| `PENDING` | Not started | Waits |
| `IN_PROGRESS` | Actively working | Monitors |
| `BLOCKED` | Cannot proceed | Investigates |
| `TESTING` | Running tests | Waits |
| `COMPLETE` | All done, tests pass | **Merges your branch** |
| `FAILED` | Unrecoverable error | Investigates |

**When you log `[COMPLETE]`, the supervisor will merge your feature to main.**

---

## Your Main Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                     WORKER WORKFLOW                              │
│                                                                  │
│  ┌──────────────┐                                                │
│  │ Check Inbox  │◄─────────────────────────────────────┐         │
│  └──────┬───────┘                                      │         │
│         │                                              │         │
│    ┌────┴────┐                                         │         │
│    ▼         ▼                                         │         │
│  Empty    FIX_TASK                                     │         │
│    │         │                                         │         │
│    ▼         ▼                                         │         │
│  ┌──────────────┐  ┌──────────────┐                    │         │
│  │ Read Spec    │  │ Fix Issues   │                    │         │
│  │ Implement    │  │ from QA      │                    │         │
│  └──────┬───────┘  └──────┬───────┘                    │         │
│         │                 │                            │         │
│         └────────┬────────┘                            │         │
│                  ▼                                     │         │
│         ┌──────────────┐                               │         │
│         │ Log Status   │                               │         │
│         │ IN_PROGRESS  │                               │         │
│         └──────┬───────┘                               │         │
│                │                                       │         │
│                ▼                                       │         │
│         ┌──────────────┐                               │         │
│         │ Work...      │                               │         │
│         │ Commit...    │                               │         │
│         └──────┬───────┘                               │         │
│                │                                       │         │
│                ▼                                       │         │
│         ┌──────────────┐                               │         │
│         │ Tests Pass?  │                               │         │
│         └──────┬───────┘                               │         │
│           Yes  │  No                                   │         │
│                ▼                                       │         │
│         ┌──────────────┐                               │         │
│         │ Log COMPLETE │                               │         │
│         └──────┬───────┘                               │         │
│                │                                       │         │
│                ▼                                       │         │
│         ┌──────────────┐                               │         │
│         │ Check Inbox  │ (wait for potential FIX_TASK) │         │
│         │ Periodically │───────────────────────────────┘         │
│         └──────────────┘                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Instructions

### Phase 1: Check Inbox

**Always check inbox first!**

```bash
cat .claude/inbox.md
```

Look for commands from supervisor:
- If `FIX_TASK` → go fix those issues
- If empty → continue with normal work

### Phase 2: Read Your Spec

```bash
cat .claude/FEATURE_SPEC.md
```

Understand your acceptance criteria.

### Phase 3: Log Start

```bash
echo "$(date -Iseconds) [IN_PROGRESS] Starting implementation" >> .claude/status.log
```

### Phase 4: Implement

Work through your spec:

1. **Create types/interfaces** → commit
2. **Implement core logic** → commit
3. **Add tests** → commit
4. **Run tests** → fix if needed → commit

```bash
# Example commit flow
git add src/auth/auth.types.ts
git commit -m "feat(auth): add type definitions"

git add src/auth/auth.service.ts
git commit -m "feat(auth): implement auth service"

git add src/auth/__tests__/
git commit -m "test(auth): add unit tests"
```

### Phase 5: Periodic Inbox Check

**Every 10-15 minutes**, check your inbox:

```bash
# Quick check
if grep -q "FIX_TASK" .claude/inbox.md 2>/dev/null; then
  echo "FIX_TASK received! Reading..."
  cat .claude/inbox.md
fi
```

### Phase 6: Run Tests

```bash
echo "$(date -Iseconds) [TESTING] Running test suite" >> .claude/status.log

npm test
```

### Phase 7: Log Complete

When all acceptance criteria are met and tests pass:

```bash
echo "$(date -Iseconds) [COMPLETE] All acceptance criteria met, tests passing" >> .claude/status.log
```

**Once you log COMPLETE:**
1. Supervisor will merge your branch to main
2. QA will eventually test the merged code
3. If QA fails, you'll get a `FIX_TASK` in your inbox
4. Keep checking inbox periodically!

---

## Handling FIX_TASK

When you see `FIX_TASK` in your inbox:

```markdown
# Command: FIX_TASK
Timestamp: 2024-01-23T11:00:00Z
Failed Standard: STD-U001 - No Console Errors
Error: TypeError: Cannot read property 'user' of undefined
Location: src/auth/auth.service.ts:42
Action: Fix the issue, commit, mark COMPLETE.
```

**Your response:**

```bash
# 1. Acknowledge
echo "$(date -Iseconds) [IN_PROGRESS] Working on FIX_TASK: STD-U001" >> .claude/status.log

# 2. Fix the issue
# ... make your changes ...

# 3. Test
npm test

# 4. Commit
git add -A
git commit -m "fix(auth): resolve console error in auth service"

# 5. Mark complete again
echo "$(date -Iseconds) [COMPLETE] Fixed QA issues, tests passing" >> .claude/status.log

# 6. Clear the task from inbox (optional)
# The supervisor will send new tasks as needed
```

---

## Message Format Reference

### FIX_TASK (supervisor → you)
```markdown
# Command: FIX_TASK
Timestamp: 2024-01-23T11:00:00Z
Failed Standard: STD-U001 - No Console Errors
Error: TypeError: Cannot read property 'user' of undefined
Location: src/auth/auth.service.ts:42

## Action Required
1. Fix the console error
2. Test locally
3. Commit your fix
4. Update status to COMPLETE
```

### BACK_MERGE (supervisor → you)
```markdown
# Command: BACK_MERGE
Timestamp: 2024-01-23T10:00:00Z
Message: Main branch updated with api feature.
Action: Changes merged automatically. Continue your work.
```

### Status Log (you → supervisor)
```
2024-01-23T09:00:00Z [PENDING] Worktree initialized
2024-01-23T09:05:00Z [IN_PROGRESS] Starting implementation
2024-01-23T09:30:00Z [IN_PROGRESS] Types complete, working on service
2024-01-23T10:00:00Z [TESTING] Running test suite
2024-01-23T10:05:00Z [COMPLETE] All acceptance criteria met
2024-01-23T11:00:00Z [IN_PROGRESS] Working on FIX_TASK: STD-U001
2024-01-23T11:15:00Z [COMPLETE] Fixed QA issues
```

---

## Git Workflow

### Commit Message Format
```
type(scope): description

feat(auth): add user login endpoint
test(auth): add unit tests for login service
fix(auth): handle null token case
refactor(auth): extract validation logic
```

### Commit Frequency

Commit after:
- Creating type definitions
- Implementing a major function/class
- Adding tests
- Fixing a bug
- Any significant milestone

### Feature Boundaries

**Your directory**: `src/<your-feature>/`

**Do NOT modify**:
- Files outside your feature directory
- Shared types (log BLOCKED instead)
- Other features' code
- Root config files

---

## Critical Rules

1. **Check inbox first** and periodically
2. **Log status changes** - supervisor is watching
3. **Commit frequently** - small, focused commits
4. **Stay in your lane** - only modify your feature directory
5. **Act on FIX_TASK immediately** - QA cycle is waiting
6. **Keep checking inbox after COMPLETE** - you may get fix tasks

---

## Start Now

1. `cat .claude/inbox.md` - check for commands
2. `cat .claude/FEATURE_SPEC.md` - read your requirements
3. Log `[IN_PROGRESS]` and start implementing
4. Commit frequently, check inbox periodically
5. When done, log `[COMPLETE]` and keep checking inbox
