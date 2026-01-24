# Feature Specification: ghcliautopragent

## Meta
- **Feature ID**: FEAT-202601241849
- **Created**: 2026-01-24

## Overview
After the back and forth between the supervisor and the QA agents stops and everything is actually done, we should add an extra step which will ask Claude to raise a PR to GitHub if GitHub CLI is present and authenticated and our feature's QA passed with flying colors.

## Acceptance Criteria
- [x] AC-1: After QA passes (QA_COMPLETE detected), check if `gh` CLI is installed using `command -v gh`
- [x] AC-2: Check if `gh` CLI is authenticated using `gh auth status`
- [x] AC-3: Check if there's a remote origin configured using `git remote get-url origin`
- [x] AC-4: If all conditions met, create a PR using `gh pr create` with appropriate title and body
- [x] AC-5: Log success/failure of PR creation to supervisor.log
- [x] AC-6: PR creation should be optional/non-blocking - project still completes even if PR creation fails

## Technical Notes
- Implementation modifies `/templates/SUPERVISOR.md` to add Phase 5.5 (Create PR) after QA passes
- Uses `gh pr create --fill` to auto-populate title and body from commits
- Falls back gracefully if gh CLI is not available or not authenticated
- PR creation happens after QA passes but before PROJECT_COMPLETE marker

## Definition of Done
- [x] All acceptance criteria met
- [x] SUPERVISOR.md template updated with PR creation logic
- [x] Status logged as COMPLETE
