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

## All P1 + P2 complete ✅

---

## 🟢 P3 — Good Features, Schedule When Ready

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

## Analytics Queries (run weekly)

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

-- Feedback this week
SELECT rating, COUNT(*) as n FROM feedback
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY rating ORDER BY rating DESC;
```


