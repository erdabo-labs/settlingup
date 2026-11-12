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

## Initial gaps / release gates (see confirmed failure below)

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

## November 11 follow-up: concrete phone error and further repairs

The owner's phone screenshot now supplies the underlying server error: **CKErrorDomain 12 / CKInternalErrorDomain 2006: `Cannot create new type cloudkit.share in production schema`** while saving `cloudkit.zoneshare`. Other saves/deletes in that atomic request then fail with code 22 / 2024. This establishes a missing share record type for that request; the earlier RecordDelete / `_pcs_data` log alone did not establish it.

Read-only CloudKit Console inspection confirms that Development and Production list only `CD_SUEntry`, `CD_SUTab`, and `Users`. Production has `CD_moveReceipt` and `CD_moveReceipt_ckAsset` on both Core Data types. Those fields are not the missing type reported by this phone error. No schema was deployed or reset in this follow-up.

[Apple DTS describes this exact cloudkit.share failure](https://developer.apple.com/forums/thread/841618): successfully create a Development share to generate the system type, then review the schema deployment difference. Do not reset the environment even though the forum discusses that as a fallback. The owner prohibits resets. If Console still offers no difference after the type exists, preserve evidence and use Apple support rather than deleting data.

The simulator currently shows **Apple Account Verification**, requiring the owner to finish password verification in simulator Settings. An account-status response of Available did not establish that share operations could finish. The owner elected to do verification later. The pending diagnostic app was stopped; neither Development share creation nor a production retry was verified. Physical-device command-line diagnostics also require Developer Mode, and `log collect` requires administrator authentication; neither setting was changed.

Further native repairs implemented:
- Custom allocations follow the actual web round-each-share and correction order, including floating-point tie order. For the web's pathological negative-correction case with many penny-sized bases, native falls back to exact largest-remainder allocation to conserve money and avoid negative shares. Existing saved allocations are not recalculated.
- Tax/tip input follows the web's bottom-driven behavior after Split evenly; new drafts reset that state. Fresh tabs require a payer, Personal requires a recipient, and saving clears the Personal recipient.
- Removing a person cleans up legacy zero-base references without invalidating the library or changing surviving shares. New custom drafts omit zero bases.
- Decimal-pad input accepts `.50` and `12.`. Website codes, short-code links and legacy `#v2` links can be opened on the existing website through Find a website tab. No Supabase integration or migration was added to native.
- Nested diagnostics include Core Data detailed/multiple underlying errors, plus event/store identifiers. The error footer is bounded so a large diagnostic cannot occupy the whole screen; complete event text remains in Settings.

Validation: the final Release simulator build succeeds with the new diagnostic/preview strings excluded from its binary. 38 regression tests pass on iPhone 17e, including actual-web custom rounding vectors, penny-allocation conservation, custom edits and payments surviving disk reopen, zero-base person removal, Smart tie order, link validation, and nested diagnostic extraction. A preceding 36-test version passed on the Duo simulator. The 375-point resizable expense viewport was visually inspected in light mode; the existing 390-point home/expense views were inspected in dark/light mode. Full folded/unfolded Duo, large text, VoiceOver, form interaction and real-device acceptance remain outstanding. Resizable session screenshots after relaunch were not accepted as Duo verification because the session ended. Do not infer complete visual parity from these checks.

DEBUG-only `--sample-data --preview-tab` / `--preview-settle` expose deterministic local views for inspection. DEBUG-only `--initialize-sharing-schema` uses an in-memory app store and a separate private zone named `SettlingUpDevelopmentSharingDiagnostic`; it does not use native tab records or invite anyone. Run this helper **only with Development CloudKit entitlements**, after simulator account verification. Its server save has not succeeded yet. Normal launches do not execute it, and Release excludes it. The separate `--cloud-diagnostic` directory and any test cloud records were retained.

Next cloud steps: finish simulator verification; create and confirm the Development `cloudkit.share` type; review the exact additive deployment difference and obtain owner approval under AGENT.md; deploy only that reviewed change; retry the existing phone installation without reinstalling; verify upload/download with a second device, then acceptance and bidirectional edits with a second account. No further TestFlight build or upload was prepared.
