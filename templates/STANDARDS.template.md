# User Experience Standards

Every standard is a user action or flow. QA tests the app like a real human user would.

**Philosophy:** Workers and Supervisor handle ALL code quality (tests, lint, TypeScript, builds, dependencies). By the time QA runs, the app MUST build and run. QA only validates user experience.

---

## App Launch

### STD-001: App Loads Without Errors
**User Action:** Open the app URL in a browser.
**Expected:** The app loads and displays the initial screen without any visible errors or blank pages.
**Verification:** Open browser, navigate to app URL, observe the page loads correctly.

### STD-002: Initial Screen is Usable
**User Action:** View the first screen after the app loads.
**Expected:** The user can see and understand the interface. Key elements are visible and not obscured.
**Verification:** Confirm main UI elements are visible and the user knows what to do next.

---

## Navigation

### STD-003: Navigation Links Work
**User Action:** Click on navigation links (menu items, sidebar, header links).
**Expected:** Each link navigates to the expected destination without errors.
**Verification:** Click each navigation element and verify it goes to the right place.

### STD-004: User Can Navigate Between Sections
**User Action:** Move between the main sections of the app.
**Expected:** User can freely navigate forward and backward through the app sections.
**Verification:** Navigate to different sections and back, verify no dead ends.

---

## Core User Flows

### STD-005: Primary User Action Completes
**User Action:** Perform the main action the app is built for (e.g., submit a form, create an item, complete a transaction).
**Expected:** The action completes successfully with appropriate feedback.
**Verification:** Execute the primary flow end-to-end and confirm success.

### STD-006: Secondary Actions Work
**User Action:** Perform supporting actions (edit, delete, search, filter, etc.).
**Expected:** Each action completes as expected.
**Verification:** Test each secondary action and verify the result.

### STD-007: Data Displays Correctly
**User Action:** View data that the app displays (lists, details, dashboards).
**Expected:** Data appears correctly formatted and readable.
**Verification:** Check that displayed data is accurate and well-formatted.

---

## Error States

### STD-008: Invalid Input Shows Error
**User Action:** Enter invalid data in forms (wrong format, missing required fields).
**Expected:** The app shows a helpful, user-friendly error message.
**Verification:** Submit invalid input and verify error messages are clear and helpful.

### STD-009: Network Errors Are Handled
**User Action:** Trigger a network failure scenario (if testable).
**Expected:** The app shows a user-friendly message, not a crash or technical error.
**Verification:** If possible, test offline behavior or API failure handling.

### STD-010: User Can Recover From Errors
**User Action:** After encountering an error, try to continue using the app.
**Expected:** The user can recover and continue without refreshing or restarting.
**Verification:** After an error, verify the app remains usable.

---

## Visual and Interaction

### STD-011: Buttons Respond to Clicks
**User Action:** Click buttons in the interface.
**Expected:** Buttons provide visual feedback and trigger their actions.
**Verification:** Click buttons and verify they respond and work.

### STD-012: Forms Submit Correctly
**User Action:** Fill out and submit forms.
**Expected:** Form data is accepted and processed correctly.
**Verification:** Complete form flows and verify data is saved/sent.

### STD-013: Loading States Are Visible
**User Action:** Trigger actions that require loading (API calls, page transitions).
**Expected:** The user sees loading indicators during waits.
**Verification:** Observe that loading states appear during async operations.

### STD-014: Interface is Responsive
**User Action:** Use the app on different screen sizes (if applicable).
**Expected:** The app remains usable on mobile and desktop viewports.
**Verification:** Test at common viewport sizes (mobile, tablet, desktop).

---

## Verification Summary

| ID | User Flow | How to Test |
|----|-----------|-------------|
| STD-001 | App loads | Open URL, check page loads |
| STD-002 | Initial screen usable | View first screen, check clarity |
| STD-003 | Navigation works | Click all nav links |
| STD-004 | Section navigation | Move between sections |
| STD-005 | Primary action | Complete main user flow |
| STD-006 | Secondary actions | Test edit, delete, search, etc. |
| STD-007 | Data displays | Check lists and details |
| STD-008 | Invalid input error | Submit bad data, check message |
| STD-009 | Network error | Test offline/failure handling |
| STD-010 | Error recovery | Continue after error |
| STD-011 | Buttons work | Click and verify |
| STD-012 | Forms submit | Complete form flows |
| STD-013 | Loading states | Observe spinners/indicators |
| STD-014 | Responsive | Test multiple viewports |

---

## Adding Project-Specific Standards

Add standards specific to your project below. Follow the same format:

```markdown
### STD-XXX: [User Flow Name]
**User Action:** What the user does.
**Expected:** What should happen.
**Verification:** How to test it.
```

**Examples:**

```markdown
### STD-015: User Can Log In
**User Action:** Enter credentials and click login.
**Expected:** User is authenticated and sees the dashboard.
**Verification:** Log in with valid credentials, verify dashboard appears.

### STD-016: User Can Add Item to Cart
**User Action:** Click "Add to Cart" on a product.
**Expected:** Item appears in cart with correct quantity.
**Verification:** Add item, open cart, verify item is present.
```

---

## What NOT to Include

These are handled by Workers and Supervisor, NOT QA:

- Unit test pass/fail
- Code coverage percentages
- Linting errors
- TypeScript errors
- Bundle size limits
- Build output checks
- TODO/FIXME comments
- API documentation
- README completeness
- Hardcoded secret scans

QA is a **human user simulator**. If a human user wouldn't check it, QA doesn't check it.
