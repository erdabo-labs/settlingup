# Release preparation

Status: native implementation prepared for local review. **Not uploaded, not signed for distribution, and not yet verified with two iCloud accounts.** Do not shut down the website or Supabase as part of this milestone.

## Apple setup

1. Open `SettlingUp.xcodeproj`. Select the SettlingUp target and your existing Apple Developer team. The project carries the same team identifier as the Flipbook reference; confirm it is the intended team. The proposed bundle ID is `com.erdabolabs.SettlingUp`; confirm it is available before registering. If changing it, update the target and test bundle identifiers, entitlement container identifier, and `TabStore.cloudIdentifier` consistently.
2. In Signing & Capabilities, enable **iCloud → CloudKit**, create/select `iCloud.com.erdabolabs.SettlingUp`, and enable **Push Notifications**. Background remote notifications and `CKSharingSupported` are already declared. Use automatic signing and let Xcode provision the registered capabilities. No Apple account credentials belong in this repo.
3. Build and run a signed development build on two iPhones signed into **different** iCloud accounts. iCloud must be available on both phones. Check Console/CloudKit events for setup errors. Never use the production schema for development writes.
4. Create a development tab, people, all three split modes, tax/tip, and recorded payments, and exercise sharing. Ensure the development CloudKit schema includes every attribute and relationship for `SUTab` and `SUEntry`, plus Core Data's generated record types. If using `initializeCloudKitSchema(options:)` from the debugger or a temporary development tool, run it **only in development**, never in normal production startup.
5. In CloudKit Console, inspect and deploy the verified **schema** to Production before TestFlight. Development data is not migrated by schema deployment. Do not reset or delete a container to troubleshoot a live app.
6. Create an App Store Connect record using the chosen bundle ID. Confirm display name availability, distribution region, age rating, privacy answers and support/privacy URLs. Review the bundled privacy manifest against the final binary and current App Store questions.

References: [Apple Core Data sharing](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users), [CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Acceptance checklist before inviting testers

- [ ] Create/edit/reopen a local tab, terminate/relaunch, verify no records lost.
- [ ] Reinstall/update behavior understood; export a backup before deleting an app. Do not use deleting/reinstalling as a recovery strategy for unsynced local data.
- [ ] Send and accept a private invitation between two Apple accounts, with the recipient app closed and already open.
- [ ] Verify only invited accounts can access the tab; invitation permissions are read/write and public sharing is disabled.
- [ ] Add different expenses simultaneously, sync, and verify both are present on both phones.
- [ ] Edit the same expense, including offline edits. Confirm conflict behavior is understandable and no silent financial discrepancy remains.
- [ ] Record the same suggested payment simultaneously on both phones; verify it is counted once. Repeat with one device behind on sync, inspect history and resolve duplicates explicitly.
- [ ] Test airplane mode, reconnect, app background/foreground, iCloud unavailable/quota failures, and a revoked invitation.
- [ ] Add an expense/person after sharing; verify new records are in the same shared graph and visible to the recipient.
- [ ] Owner stops sharing: private copy retained, participant access removed, no old shared tab reappears after relaunch. Participant leaves: owner's data remains.
- [ ] Backup export/restore preserves amounts, split metadata, people, dates, payment history and balances; restore cannot overwrite a nonempty library.
- [ ] Delete private tab: synced devices remove it; other unrelated tabs remain.
- [ ] Check folded/unfolded Duo in both orientations, smallest supported iPhone, standard iPhone and Pro Max, with keyboard and long names/amounts.
- [ ] Check dark/light modes, accessibility text sizes, VoiceOver navigation, reduced motion, sufficient contrast and reachable controls.
- [ ] Confirm native UI contains no developer placeholders and screenshots are representative.

## TestFlight and App Store

1. After the checklist passes, archive the **Release** configuration for a generic iOS device with signing enabled. This checkout is version **0.1.0**, build **1**. Increment the build for each upload.
2. Validate the archive in Organizer. Check entitlements include the intended iCloud container, CloudKit and production push configuration after distribution signing; development builds use development push entitlements.
3. Upload only after owner approval. TestFlight/App Store builds use the **production** CloudKit environment. Repeat invitation and sync tests there; passing development tests does not verify production configuration.
4. Start with internal TestFlight. External TestFlight may require Beta App Review. Supply review notes explaining that there is no SettlingUp account or payment transfer, and iCloud collaboration requires two Apple accounts.
5. Publish the reviewed privacy policy and support page, enter their HTTPS URLs, upload screenshots, complete encryption/privacy/age-rating questions and submit for review when ready. Do not claim production readiness solely from an unsigned archive.

## Website retirement

The native app does not read or write existing Supabase tabs. Existing web links cannot become iCloud invitations automatically. Leave the website running until the owner has decided how to handle old tabs and notified affected users if needed. Any backend export, schema/security change, Vercel route change or shutdown is a separate explicit action.
