# SettlingUp — Mission & Operating Principles

## Native iPhone direction — approved October 29, 2026

Build a simple native app for the owner and friends. On-device persistence and Apple iCloud sharing replace the native app's need for Supabase/Vercel. iPhone/iCloud-only collaboration is acceptable; broad cross-platform growth and monetization are not goals of this migration. Distribute through TestFlight first, with public App Store release optional after verification. The existing web service described below stays operational and unchanged during development. Its technology constraints apply to the website, not the separately approved SwiftUI/Core Data/CloudKit target.

## What This App Is

SettlingUp is a zero-friction expense splitting web app. No accounts, no downloads, no
sign-ups. You create a tab, add people, log expenses, and share a link. Everyone sees
exactly who owes what and how to settle up with the fewest possible payments.

The entire app is a single HTML file with vanilla JavaScript, backed by Supabase for
real-time sync and Vercel for hosting. There is no build step, no framework, no native
app. It works in any browser on any device.

## Who It's For

People in the middle of a real situation — splitting a trip, a dinner, a household bill —
who need an answer in under two minutes without creating an account or installing anything.
They share a link and the whole group is on the same page instantly.

## The Mission

**Reliable, easy, and free. Always.**

Every decision about features, design, and monetization should be tested against those
three words in that order. Reliable first. If something makes the app faster or more
correct but slightly harder to use, do it. If something makes money but makes the app
less reliable, don't.

## What Success Looks Like

- Tabs are created and shared without friction
- The math is always correct to the cent
- Share links always work
- The app loads fast on a phone with a mediocre connection
- People come back because it worked last time
- Organic growth through shared links (every tab = at least 2 new visitors)

## Monetization Principles

The app is free and will stay free for core use. Acceptable monetization:

- **Tip jar / "buy me a coffee"** — optional, never prompted aggressively
- **Contextual "Paid ✓" moment tip** — shown once after settling, skippable in one tap
- **Venmo/Cash App deep links** — earn referral where possible; primarily a UX feature
- **"Powered by SettlingUp" on exports** — earned advertising, not paid
- **Optional Pro one-time unlock** ($2.99) for PDF export, expense categories, extended
  tab life — no subscription, no recurring charge

Never acceptable:
- Paywalling core functionality
- Ads of any kind
- Selling or sharing user data
- Dark patterns, fake urgency, guilt trips
- Anything that makes a paying user's experience better at the expense of a free user's
  reliability

## Technology Constraints

- **Single file**: All app code lives in `index.html`. No build step, no bundler.
- **No new dependencies**: The CDN-loaded libs (Supabase JS, Outfit/JetBrains fonts)
  are the only external dependencies. Do not add npm packages that end up in the browser.
- **Vanilla JS only**: No React, Vue, TypeScript, or frameworks in `index.html`.
- **Supporting files**: `settlingup-demos.js`, `vercel.json`, `package.json`,
  `manifest.json`, `og-image.png` are the only other files in the repo root.
- **Supabase schema** (do not change without owner approval):
  - `tabs`: id, short_code, tab_name, people (jsonb), person_id_seq, owner_token_hash,
    created_at, updated_at
  - `expenses`: id (GENERATED ALWAYS AS IDENTITY), tab_id, description, amount,
    paid_by, split_type, split_with (jsonb), split_amounts (jsonb), created_at
  - `payments`: id (GENERATED ALWAYS AS IDENTITY), tab_id, from_person_id,
    to_person_id, amount, created_at
  - RLS: permissive allow_all policies on all tables (anon key access)

## Design Principles

- Dark mode default, clean light mode available
- Cyan (#00d4ff) accent — never change this
- Numbers in JetBrains Mono, UI in Outfit
- Mobile-first, 480px max-width app shell
- Every interaction should feel instant
- Error states are inline, never alert() dialogs
- Animations are subtle — nothing that delays a user getting to their answer

## What the Agent Should Never Do Without Owner Approval

- Change the Supabase schema
- Change the short code format or URL structure
- Modify the RLS policies
- Add new external CDN dependencies
- Change the primary accent color
- Delete any data from production
- Modify `vercel.json` routing rules
- Push directly to `main` — always use a branch and open a PR
- Modify billing or Stripe configuration

## Owner

Data engineer by trade, not a front-end developer. Comfortable reading diffs and
reviewing PRs. Wants to spend < 30 minutes per week on this project. Prefers to be
contacted via Telegram with a short brief before any work starts. Will approve or reject
via Telegram. Merges PRs himself.
