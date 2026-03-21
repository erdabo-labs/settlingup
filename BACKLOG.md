# SettlingUp — Product Backlog

> Maintained by the agent. Owner reviews and re-prioritizes on demand.
> Format: each item has a status, size estimate, and enough context to execute without
> asking basic questions. Items marked NEEDS-DECISION require owner input before starting.

---

## Status Legend

- `[ ]` — not started
- `[~]` — in progress (include branch name)
- `[x]` — done (include PR or commit)
- `[?]` — blocked / needs owner decision
- `[-]` — won't do / deprioritized

---

## 🔴 P1 — Do These First

All P1 items are complete. ✅

---

## 🟡 P2 — High Value, Ship Soon

### [ ] Replace alert() with inline form errors
**Size:** M
**Why:** alert() is jarring on mobile. Every validation failure pops a native dialog.
**What to do:**
- Add `div#expense-form-error` below the "+ Add expense" button, hidden by default
- Style: `font-size:12px; color:var(--red); margin-top:8px; text-align:center;`
- Replace all `alert()` in `addExpense()` with `showFormError('message')`
- Flash red border on the specific missing field
- Auto-clear after 4 seconds or on next interaction

### [ ] Home screen value prop for first-time visitors
**Size:** S
**Why:** First-time visitors see "Name your tab / What's the occasion?" with zero context.
**What to do:**
- Add above `.section-title` on step 0, only when `su-recent-tabs` is empty in
  localStorage:
  ```html
  <div class="hero-tagline">
    Split any expense. Settle up fairly.<br>
    <span>No sign-up. No app. Just share a link.</span>
  </div>
  ```
- Style: centered, large-ish font, muted subtext, fades in with the step animation
- Hide it once the user has any recent tabs (returning users don't need it)

### [ ] Sub-dollar balance treatment
**Size:** S
**Why:** "Chris owes $0.82" creates real-world awkwardness. Tiny residuals should be
visually softened.
**What to do:**
- In person card rendering: if `Math.abs(bal) < 1.00` and `bal !== 0`, add class
  `is-micro` to the card
- `.person-card.is-micro { opacity: 0.65; }`
- Change verdict text to "basically settled ($0.82)" in muted color

---

## 🟢 P3 — Good Features, Schedule When P1+P2 Done

### [ ] Venmo / Cash App deep links on payment cards
**Size:** M
**Why:** Users are about to open Venmo anyway. Pre-filling the amount is a genuine
time-saver and a natural monetization hook.
**What to do:**
- Add a "Pay on Venmo" button to each payment card (only shown for the current user's
  outgoing payments)
- Venmo deep link: `venmo://paycharge?txn=pay&recipients=&amount=${pay.amount}&note=SettlingUp`
- Cash App: `https://cash.app/$<tag>/${pay.amount}`
- Store optional Venmo/CashApp handle in identity (localStorage per tab)
- If no handle set: show button greyed with "Add your Venmo" tooltip
- NEEDS-DECISION: Design of the handle input UX

### [ ] Tip jar / "buy me a coffee" moment
**Size:** S
**Why:** Contextual ask at the highest-value moment — right after settling.
**What to do:**
- On first load of step 3 (settle page), if `su-tipped` not in localStorage, show a
  dismissable card at the bottom of the payments list:
  *"SettlingUp saved you the math 🧮 Buy the developer a coffee?"*
  with $1 / $3 / $5 Stripe links and a "Maybe later" dismiss
- Set `su-tipped=dismissed` on dismiss; `su-tipped=yes` on click
- Never show again after either action
- NEEDS-DECISION: Stripe account and payment links

### [ ] Expense list search/filter
**Size:** M
**Why:** With 20+ expenses, finding one to edit is painful.
**What to do:**
- Show a search input above the expense list only when `state.expenses.length >= 8`
- Filter in real time by description (case insensitive)
- Clear button on the input
- "No expenses match" empty state

### [ ] Tab expiry warning
**Size:** M
**Why:** Tabs will be deleted after 90 days (future cron job). Users should know.
**What to do:**
- Add `last_accessed_at` column to tabs table (NEEDS-DECISION: schema change)
- Update it on every tab load
- On settle page: if tab is 80+ days old, show warning banner:
  "This tab expires in X days — reshare the link to keep it active."

### [ ] PDF / share export
**Size:** L
**Why:** Groups want to send a clean summary. High perceived value.
**What to do:**
- "Export summary" button on settle page
- Generates a clean HTML print view: tab name, date, total, payment list, breakdown
- "Powered by settlingup.app" footer
- `window.print()` or jsPDF (CDN) — NEEDS-DECISION on approach
- This is the Pro feature unlock candidate

### [ ] Duplicate expense warning
**Size:** S
**Why:** Users adding expenses manually often accidentally duplicate them.
**What to do:**
- In `addExpense()`: before saving, check if any existing expense has the same
  description (case insensitive) AND same amount
- If match found: show inline warning (not blocking): "You already have a
  '[desc]' for $X — is this a duplicate?" with "Add anyway" / "Cancel" buttons

---

## 🔵 P4 — Future / Needs More Thought

### [ ] Payment notes when marking done
Memo field ("Sent on Venmo") saved to payments table. Requires DB column addition.

### [ ] Delete a tab
Owner-only, uses localStorage token. Confirm dialog, cascade delete in Supabase.

### [ ] Currency selector
Tab-level USD/EUR/GBP/CAD/AUD/JPY picker. Store in tabs table. New column required.

### [ ] Expense categories + breakdown chart
Tag each expense (Food, Transport, etc.). Donut chart on settle page. Pro feature candidate.

### [ ] Offline queue / retry
Failed saves retry automatically. Local queue with persistent state.

### [ ] Dynamic OG meta per tab
Vercel edge function reads tab from Supabase, renders tab-specific og:title/description.

### [ ] Tab summary read-only page
`/t/<code>/summary` — clean read-only settle view for sending to non-participants.

### [ ] Viewer mode
Skip identity picker, browse tab without being a participant.

### [ ] Service worker / PWA caching
Cache current tab's data. Works offline.

---

## Analytics Queries to Run Weekly

The agent should run these against Supabase and include results in the weekly brief:

```sql
-- New tabs this week
SELECT COUNT(*) FROM tabs
WHERE created_at > NOW() - INTERVAL '7 days';

-- Total active tabs (accessed in last 30 days)
SELECT COUNT(*) FROM tabs
WHERE updated_at > NOW() - INTERVAL '30 days';

-- Total expenses added this week
SELECT COUNT(*) FROM expenses
WHERE created_at > NOW() - INTERVAL '7 days';

-- Average expenses per tab (active tabs)
SELECT AVG(exp_count) FROM (
  SELECT tab_id, COUNT(*) as exp_count FROM expenses
  GROUP BY tab_id
) sub;

-- Split type breakdown
SELECT split_type, COUNT(*) as n FROM expenses
GROUP BY split_type ORDER BY n DESC;

-- Tabs by people count (from jsonb array length)
SELECT jsonb_array_length(people) as people_count, COUNT(*) as tabs
FROM tabs GROUP BY people_count ORDER BY people_count;
```

---

## How to Update This File

When completing an item:
1. Change `[ ]` to `[x]`
2. Add the PR number or commit hash as a note
3. Move it to a `## Done` section at the bottom (keep last 10, archive the rest)

When adding a new item from analytics or user feedback:
1. Add it in the right priority tier with full context
2. Flag it in the weekly brief to the owner
3. Don't start it until the owner acknowledges

When re-prioritizing:
1. Move items between tiers
2. Note the reason for the change
3. Message the owner with the proposed re-prioritization before acting on it

---

## ✅ Done

### [x] Penny rounding — whole-cent splits everywhere
**Done:** PRs #11, #12 — `splitEvenly()` helper with integer cent arithmetic + ID-seeded rotation for fair penny distribution across expenses.

### [x] markDone() uses list index, not stable payment identity
**Done:** PR #12 — chip id is `done-${pay.from}-${pay.to}`; `markDone()` takes element + pay object; marked state persists across re-renders.

### [x] editExpense() leaves top amount field blank
**Done:** PR #12 — `editExpense()` sets `exp-amount-top` to `exp.amount.toFixed(2)`; `cancelEdit()` clears it.

### [x] goHome() silently destroys unsaved local-mode data
**Done:** PR #10 — `goHome()` shows confirm dialog when not on step 0, has unsaved people/expenses, and no tabId.

### [x] Realtime INSERT race: _pendingLocalIds never checked
**Done:** PR #10 — INSERT handler returns early if `_pendingLocalIds.size > 0`.

### [x] Keyboard Enter submits expense form
**Done:** PR #10 — `onkeydown` Enter handler on `#exp-desc`, `#exp-amount-top`, `#exp-tax`, `#exp-tip`.

### [x] "You" card accent border + badge on settle page
**Done:** PR #10 — `.person-card.you-card { border-color: var(--accent) }` + `.you-badge` span in card header.

### [x] "New tab" button danger styling
**Done:** PR #10 — `btn-new-tab` class on button + `.btn-ghost.btn-new-tab:hover { color: var(--red) }` CSS rule.

### [x] Person removal confirmation shows amounts
**Done:** PR #10 — affected expenses listed as `• ${e.desc} (${fmt(e.amount)})`.

### [x] PWA manifest — move from data URI to real file
**Done:** PR #11 — `/manifest.json` created; `<link rel="manifest">` updated to use file path. Fixes Android "Add to Home Screen".

### [x] Check og-image.png exists in repo root
**Done:** `og-image.png` confirmed present in repo root.
