# Native migration repair — November 10, 2026

The original migration changed the product without preserving its workflows. Build 0.1.0 (1) is not a faithful replacement for the website and is not release-ready. The owner also reports a CloudKit “Failed to modify some records” error. Schema deployment and a successful TestFlight upload did not establish working synchronization.

## Source of truth

`index.html` and `settlingup-demos.js` define the original interaction and calculations. Keep the four steps, cyan/navy styling, Outfit and JetBrains Mono, rounded cards, inline expense controls, and settlement breakdown. The folding layout preserves the same reading order and a bounded content width instead of switching to a sidebar/dashboard.

## Implemented in the corrective local build

- Name → people → expenses → settle navigation and the original-style home/expense cards.
- Inline description/total, payer buttons, visible Even / Custom / Personal controls.
- Include/exclude people, custom total-driven splitting, explicit Split evenly, per-person-driven total, proportional tax/tip, and live per-person previews even before a description is supplied.
- Remember payer and split mode per tab; stable entry order for newly created people; per-expense remainder rotation.
- Person rename/removal with confirmation for related expenses/payments, and per-device “You” identity.
- Smart/Direct strategy selection, persistent paid cards with undo, and individual paid/share/net calculations with expense and payment details.
- Original three demo scenarios, copied into the bundle; per-tab emoji selection stored on the device.
- Cloud events observed before store loading, separate upload/download timestamps, account status and nested error diagnostics. Setup is no longer presented as a successful data sync.
- Persistent-history merging for imported inserts/updates/deletions before refreshing the UI, following Apple TN3164.

No existing native store files or production website data were deleted. Optional JSON fields preserve compatibility with build 1 payloads. The Core Data schema itself is unchanged. DEBUG-only cloud reproduction uses a separate SettlingUp-CloudDiagnostic directory; normal device data is not used for its test fixture. Existing recorded transfers are retained, including those no longer matching the currently displayed strategy.

## Verification so far

- Corrective build compiles for iPhone Duo simulator.
- 30 money/persistence/font-registration tests passed on iPhone 17e after correcting the bundled Outfit weights. All three original website demo balance vectors match the native calculations to the cent (31 expenses total).
- New checks cover remainder rotation, custom tax/tip, Direct mark/undo, paid-card visibility, person ordering/rename, old payload decoding, and importing background context updates/deletions.
- Duo home, expense and settlement screens inspected folded/unfolded; mark paid updated individual balances and Undo restored the payment. Final font/segment styling, narrow-phone visuals, Dynamic Type and light-theme inspection remain outstanding.

## Explicit gaps / release gates

- Production CloudKit failure is **not diagnosed or fixed yet**. The deployed CD_SUTab/CD_SUEntry attributes were inspected and the expected fields exist. The initial past-week Logs query was empty; a later query returned a phone request with BAD_REQUEST during a RecordDelete operation involving the shared and private zones. The server log returned _pcs_data, which does not establish the underlying cause (Apple DTS explains this can mask a schema mismatch). Need device-level error evidence and a verified production round trip.
- Two-account invitation acceptance and collaborative edits remain unverified.
- Existing Supabase tabs, short-code lookup and web links remain on the website. They do not silently become iCloud tabs. A compatible native migration/open-web workflow still needs completion.
- Website feedback submission has no native replacement; do not send feedback to a new destination without agreement.
- Full visual comparison, accessibility checks, and exact custom-rounding edge-case comparison remain outstanding. Native custom splits use mathematically exact largest-remainder allocation; the website's legacy rounding correction can differ by a cent in tie cases.
- Owner authorized the corrective testing build on November 11. Build 0.1.0 (2) was uploaded successfully; group availability is tracked in TESTFLIGHT.md. This is a known-issue internal beta, not a claim that the release gates are complete.

## Cloud evidence still required

“Failed to modify some records” is an outer partial-failure message. The new diagnostic section exposes underlying domain/code and per-item errors when CloudKit supplies them, without including tab contents. Some production failures omit these details and require a device sysdiagnose (Apple Developer Forums thread 813983). Do not reset stores, switch cloud containers, or ask the owner to reinstall to hide the failure. Preserve the owner's local data and resolve the actual error before calling syncing ready.


## Follow-up evidence from the resumed session

- Production telemetry shows 48 requests / 5 errors for the displayed October 30–November 11 UTC period: 3 BAD_REQUEST and 2 ZONE_NOT_FOUND. Aggregate counts include setup operations and are not a diagnosis by themselves.
- Phone failure: operation B2B6E38170193774, request 6D27258A-4DCC-4113-B015-D0889759A162, iOS 27.2, PRIVATE database, RecordDelete, USER_ERROR / BAD_REQUEST. Export kept in the owner's Downloads as database-export-logs.json; do not commit user-specific cloud logs.
- Simulator production diagnostic fails earlier with NSCocoaErrorDomain 134400: CKAccountStatusTemporarilyUnavailable. This is a simulator authentication blocker, not evidence of the phone's failure cause.
- Bundled variable Outfit faces produced runtime warnings that iOS could not apply weights. Static 400/600/700/800 faces were generated from the same licensed font with scripts/build-fonts.py; SwiftUI now references explicit face names. Font registration is tested.
- Opening macOS Console to inspect the physical device was blocked by another Mac lock. Pending: unlock/keep Mac available, complete simulator Apple Account verification, collect nested phone error, finish visual checks. Do not upload as release-ready.

Primary references: [Apple TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer), [DTS explanation of misleading _pcs_data errors](https://developer.apple.com/forums/thread/842760), [production error diagnosis guidance](https://developer.apple.com/forums/thread/813983).
