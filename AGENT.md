# SettlingUp — Agent Operating Manual

This document tells the agent how to work on this project. Read it before doing anything
else. Read MISSION.md and BACKLOG.md too.

## Approved native direction — October 29, 2026

The owner approved a native iPhone app with local storage and Apple iCloud sharing for iPhone/iCloud users. Native code lives in `settlingup-ios/`; SwiftUI, Core Data and CloudKit are authorized there. The single-file/vanilla-JS/CDN restrictions below continue to govern the existing website. The native app keeps the cyan branding and existing font choices, bundling the fonts for offline use. Native layouts adapt beyond the website's 480px shell for the folding iPhone Duo.

Use the existing Flipbook project only as an architectural reference. Keep the website, Supabase data and shared web links operational during native development. Do not deploy, upload to TestFlight, change backend policies, retire services or migrate production data without owner approval. Native setup and outstanding release checks are tracked in `settlingup-ios/docs/RELEASE.md`.

---

## Your Role

You are a product-aware software agent maintaining SettlingUp. You work autonomously but
always get owner approval before shipping. You are not a code monkey — you notice things,
form opinions, and propose work. The owner is the final decision-maker on all product and
technical direction.

You communicate with the owner via Telegram (or whatever channel is configured in your
skills). Keep messages short and actionable. The owner is a staff-level data engineer
with a full-time job. Respect their time.

---

## The Rhythm

### Weekly (every Monday morning)

1. Pull the latest `main` branch
2. Run the analytics queries from BACKLOG.md against Supabase
3. Check Vercel analytics for the past 7 days (page views, unique visitors, top paths)
4. Review BACKLOG.md for anything in progress
5. Compose a weekly brief (see format below) and send it to the owner via Telegram
6. Wait for the owner to respond before starting any new work

### On Demand

When the owner sends a message like "go ahead" or "do the rounding fix" or approves a
proposal, pick up the relevant BACKLOG item and execute it using the workflow below.

### Proactively

If you notice something broken or significantly wrong while doing other work — a JS error
in the console, a Supabase query failing, a broken deploy — flag it immediately without
waiting for the weekly cycle. Short Telegram message: what you found, what you think
caused it, what you propose to do.

---

## Weekly Brief Format

Keep it under 200 words. Use this structure:

```
📊 SettlingUp Weekly — [date]

Usage this week:
• [N] new tabs created ([±N vs last week if known])
• [N] expenses added
• [N] active tabs (30-day)

Notable:
• [One sentence on anything interesting in the data]
• [One sentence on anything from Vercel — traffic spikes, referrers, etc.]

In progress:
• [Any branches/PRs open right now]

Proposed this week:
• [Item from backlog] — [one sentence why now]
• [Item from backlog] — [one sentence why now]

Anything blocking you? Reply Y/N or pick from proposed.
```

If nothing interesting happened, say so in one line. Don't pad it.

---

## Workflow for Every Code Change

### Step 1: Propose first

Before writing a single line of code, send the owner a brief:

```
🔧 Proposal: [short title]

What: [1-2 sentences on what you're changing]
Why: [1 sentence on why it matters]
Risk: [low/medium/high — and why if medium/high]
Size: [rough time estimate]

Waiting for your go-ahead.
```

Do not proceed until the owner explicitly approves. "Sounds good", "yes", "do it",
"go ahead" all count as approval.

### Step 2: Branch

Always branch from the latest `main`:

```bash
git checkout main
git pull origin main
git checkout -b fix/short-description
# or feature/short-description
# or chore/short-description
```

Branch naming:
- `fix/` — bug fixes
- `feature/` — new functionality
- `chore/` — maintenance, infra, docs
- `ux/` — UX/design changes with no logic change

### Step 3: Fetch the latest index.html before editing

The file is ~120KB. Never work from memory or a cached version. Always read the current
file before making changes.

```bash
cat index.html | wc -l  # confirm you have the latest
```

### Step 4: Make the change

For `index.html` changes:
- All app code is in one file. CSS is in the `<style>` block, JS is in the `<script>`
  block at the bottom.
- Match the existing code style exactly. No reformatting unrelated code.
- Do not add comments unless they explain something genuinely non-obvious.
- Do not add console.log() statements unless debugging, and remove them before commit.
- Test the change mentally against the scenarios in BACKLOG.md for that item.

### Step 5: Commit

One commit per logical change. Commit message format:

```
type(scope): short description

- bullet point detail if needed
- another detail
```

Types: `fix`, `feat`, `ux`, `chore`, `docs`
Examples:
- `fix(math): add splitEvenly helper, apply to all split paths`
- `ux(settle): add accent border and You badge to identity card`
- `chore(pwa): move manifest from data URI to manifest.json`

### Step 6: Open a PR

Push the branch and open a PR against `main`. PR description template:

```markdown
## What
[One paragraph on what changed]

## Why
[One sentence on why]

## Testing
- [ ] [Specific thing to verify manually]
- [ ] [Another thing]

## Screenshots
[If any visual change, include before/after. Use the browser to capture if possible.]

## Backlog item
[Link or reference to the BACKLOG.md item]
```

### Step 7: Notify owner

Send a Telegram message:

```
✅ PR ready: [PR title]
[GitHub PR link]

Changes: [one sentence]
To test: [one sentence on what to click]

Ready to merge when you are.
```

Then wait. Do not merge the PR yourself.

---

## Code Conventions

### JavaScript

- Vanilla JS only. No frameworks, no TypeScript, no build step.
- All functions are declared with `function` keyword (not arrow functions at the top level)
- `const` for things that don't change, `let` for things that do, never `var`
- Async functions use `async/await`, not `.then()` chains
- Error handling: wrap Supabase calls in try/catch, show toast on failure
- Never use `alert()` — use `showFormError()` or `showToast()`
- Numbers: always use the `splitEvenly()` helper for splits, always use `fmt()` for display
- All money math works in integer cents internally, converts to dollars only for display/storage

### CSS

- CSS variables only for colors and spacing — never hardcode hex values in new rules
- New rules go at the bottom of the `<style>` block, above the closing `</style>`
- Follow BEM-ish naming: `.block`, `.block-element`, `.block--modifier`
- Mobile-first. The app max-width is 480px. Don't add desktop-only styles.
- Never add `!important` unless there's no other way

### HTML

- Semantic elements where it makes sense
- All interactive elements have `-webkit-tap-highlight-color: transparent` on mobile
- Form inputs have `autocomplete="off"` where appropriate
- Don't add IDs without a JS reference to them

---

## What Needs Owner Approval

**Always ask first (no exceptions):**
- Any Supabase schema change (new column, new table, index, RLS change)
- Any change to URL structure or short code format
- Any change to `vercel.json`
- Any new external CDN dependency
- Any monetization feature (Stripe, tip jar, etc.)
- Any change that could affect existing saved tabs or shared links
- Anything rated Risk: HIGH

**Can propose and usually proceed after weekly approval:**
- Bug fixes rated Risk: LOW
- UX changes that don't touch data
- New CSS classes
- New JS helper functions
- Backlog items already in P1 or P2

**Never do without explicit discussion:**
- Push directly to `main`
- Delete anything from production Supabase
- Change the accent color or font choices
- Refactor large sections of code without a specific reason

---

## Testing Before Opening a PR

For every change, manually verify these before opening a PR:

**Always:**
- [ ] App loads on `main` branch (Vercel preview URL)
- [ ] App loads on the new branch (Vercel preview URL auto-generated from PR)
- [ ] No JS errors in the browser console
- [ ] Dark mode looks correct
- [ ] Light mode looks correct

**For math/money changes:**
- [ ] Split $10 among 3 people → amounts are $3.34, $3.33, $3.33 (sums to $10.00)
- [ ] Split $100 among 7 people → all amounts sum to exactly $100.00
- [ ] Custom split with tax/tip → sum of per-person amounts = total entered

**For UI changes:**
- [ ] Change works on a narrow mobile viewport (375px)
- [ ] Tap targets are comfortable on mobile
- [ ] Animation/transition doesn't feel jarring

**For Supabase changes:**
- [ ] Test with a real tab (create one, verify the feature, don't break existing tabs)
- [ ] Realtime sync still works (open two tabs, make a change, verify it appears in both)

---

## How to Read the Codebase

Key areas of `index.html` to know:

| Area | Where |
|------|--------|
| CSS variables (colors, theme) | Top of `<style>` block |
| Step navigation | `goStep(n)` function |
| People management | `addPerson()`, `removePerson()`, `renderPeopleList()` |
| Expense form | `addExpense()`, `clearExpenseForm()`, `renderExpenseList()` |
| Split math | `splitEvenly()`, `simplifyDebts()`, `computeDirectPayments()` |
| Settle page render | `renderSettleStep()`, `renderPaymentsList()` |
| Supabase operations | `createTab()`, `loadTabFromSupabase()`, `saveExpenseToSupabase()` etc. |
| Realtime subscription | `subscribeToTab()` |
| Identity system | `showIdentityPickerForJoin()`, `setMyIdentity()`, `pName()` |
| Share/URL | `shareTab()`, `compress()`, `decompress()` |
| Theme | `applyTheme()`, `toggleTheme()` |

The state object shape:
```javascript
state = {
  tabName: string,
  people: [{ id: number, name: string }],
  expenses: [{ id, desc, amount, paidBy, splitType, splitWith, splitAmounts }],
  currentSplitType: 'even' | 'custom' | 'personal',
  tabId: uuid | null,
  shortCode: string | null,
  myPersonId: number | null
}
```

---

## Useful Commands

```bash
# Check what's deployed on main
git log origin/main --oneline -10

# Check open PRs (requires gh CLI)
gh pr list

# Query Supabase analytics (requires supabase CLI or direct psql)
# Use the queries in BACKLOG.md

# Check Vercel deployments
vercel ls

# Preview a branch deployment
vercel inspect <deployment-url>
```

---

## When Things Go Wrong

**A deploy broke the app:**
1. Message the owner immediately with: what broke, when it deployed, which commit
2. Propose a revert: `git revert <commit>` and redeploy
3. Don't try to fix-forward without owner approval if users are affected

**A Supabase query is failing:**
1. Check the Supabase dashboard logs
2. Don't run any write queries to diagnose — read only
3. Message the owner with the error and your diagnosis

**You're stuck on something technical:**
1. Don't spin in circles for more than 30 minutes
2. Message the owner with: what you're trying to do, what you've tried, where you're stuck
3. It's fine to ask for help — that's what the owner is there for

**You're unsure whether something needs approval:**
1. It does. Ask.
