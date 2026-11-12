# Build 0.1.0 (2) — internal testing

Restores the original-style tab → people → expenses → settle flow, visible split controls, Smart/Direct settlements, paid/undo cards, individual breakdowns, identity, people editing and the original demos. Corrects bundled Outfit font weights.

Please test:
- Even, Custom and Personal splits, include/exclude people, custom totals, Split evenly, tax and tip.
- Edit an expense, inspect each person's share, switch Smart/Direct and mark/unmark a payment.
- Fold/unfold Duo while using the forms; check light/dark mode and larger text.
- Update the existing app and confirm saved tabs remain available.

Known issue: production iCloud syncing/sharing may still fail with “Failed to modify some records.” This build does not claim to fix that failure. Settings → iCloud status now distinguishes account availability, uploads and downloads, and offers recent events / Share sync diagnostics. Local data remains on the phone. Existing website tabs are separate and are not automatically imported.

Validation: 30 local money/persistence/font-registration tests passed. Original demo balances match to the cent. Signed Release package verified with Production iCloud/APNs, the existing bundle/container identifiers, no debugger entitlement and all registered fonts present. Development diagnostic seeding is absent from Release.
