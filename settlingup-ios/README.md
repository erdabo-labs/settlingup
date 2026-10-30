# SettlingUp for iPhone

Native SwiftUI expense splitting with durable on-device storage and optional Apple iCloud collaboration. No Supabase, Vercel, third-party SDK, developer server, advertising, analytics, or payment processing is used by the native target. The existing website and its shared links remain separate and unchanged.

## Run

Open `SettlingUp.xcodeproj` and run the **SettlingUp** scheme. Requires Xcode with the iOS 18+ SDK; this checkout was built with Xcode 27.1. The target supports iPhone, including adaptive Duo folded/unfolded layouts. Select your developer team for a physical device.

Simulators default to local-only storage so unsigned previews do not require CloudKit entitlements. Launch with `--sample-data` for an isolated, nonpersistent example tab. Physical devices default to iCloud-backed local stores. `--local-only` runs without cloud; `--enable-cloud` explicitly opts a properly signed, iCloud-configured simulator into cloud testing. Do not use production personal records for sample or migration tests.

```sh
xcodebuild -project settlingup-ios/SettlingUp.xcodeproj -scheme SettlingUp \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -derivedDataPath settlingup-ios/build CODE_SIGNING_ALLOWED=NO test
```

## Included

- Create, rename, search, and delete private tabs; add participants by name.
- Add/edit/delete expenses with even, custom, and personal splits, optional tax/tip, exact integer-cent arithmetic, and a preview.
- Suggested settlements, balances, actual payment history, and undo recording. Recording does not send money.
- Native iCloud invitations and permission management; accept invitations on cold launch or in a running app.
- Complete JSON backup export and validated, atomic restore into an empty library. Restores receive fresh tab/person/expense/payment identities and require new invitations.
- Share a text summary through the system share sheet.
- Cyan branding, bundled Outfit/JetBrains Mono fonts with licenses, dark/light/system appearance, scalable text, native forms and safe areas.

Native settlement suggestions reduce transfers using a greedy algorithm; they do not claim a mathematically minimal result. The web app's alternative Direct view is not exposed in this first native interface. All amounts are USD.

## Storage and collaboration

`NSPersistentCloudKitContainer` mirrors a private store and a shared store. A tab owns separate person, expense and transfer entries through inverse Core Data relationships. Sharing traverses only that tab's graph. No entire-library JSON document is used for sync. Expense payloads are independent records; concurrent edits to the same expense may resolve at record granularity, so avoid editing the same expense on two offline devices. A stale form is rejected if a newer expense is already present locally.

Changes save on the phone first. iCloud sync is **eventual**, not an instantaneous live session. It can take minutes or longer; the app cannot force CloudKit's schedule. The status reports local persistence and the last successful CloudKit activity, not proof every participant has every change. Offline edits retry through Apple's persistent history/mirroring system. Foreground and remote-change handling refresh local objects.

Two devices recording the same suggestion from the same ledger derive the same payment identifier; duplicate backing entries count once. Different stale ledger states can still yield different suggestions. Users should coordinate actual payments and inspect payment history; the app does not authorize or move funds. Multi-account concurrent edits remain a release acceptance test.

Stopping sharing purges the shared graph. The owner path first saves an independent private copy; a participant leaving does not keep access. That lifecycle must be verified with two real iCloud accounts before distributing a sharing-enabled build. Deleting an actively shared tab is refused; use Apple's sharing controls first.

Storage failures never reset the store. Invalid/incomplete imported data blocks edits and backup export instead of silently omitting records. A partially downloaded graph may temporarily need more time to sync. Backup import validates the complete file before mutation and commits atomically. A backup is not a live share and does not preserve CloudKit permissions.

## Next steps

Follow [release preparation](docs/RELEASE.md) to register the app/container, deploy the CloudKit production schema, validate sharing and distribute through TestFlight. [Review evidence](docs/REVIEW-2026-10-29.md) distinguishes completed checks from outstanding ones. [Privacy policy draft](docs/PRIVACY.md) and [store listing draft](docs/STORE-LISTING.md) are included for owner review.

Existing Supabase tabs are not automatically migrated. Keep the website available for those tabs. No production data, backend policies, routes, or deployments were changed.
