# Release preparation

Status: **0.1.0 (1) is available for internal TestFlight testing as of October 30, 2026.** Apple finished processing it; the Personal group shows **1 Tester · 1 Build**, with the build status **Testing**. The owner account is the sole tester. It is not a public App Store release and two-account collaboration acceptance checks remain outstanding. The App ID and matching CloudKit container are registered and linked; Core Data generated the development schema and it was deployed to Production. Production record types `CD_SUEntry` and `CD_SUTab` were verified in CloudKit Console. Do not repeat these registrations or shut down the website or Supabase as part of this milestone.

App Store Connect listing: **SettlingUp: Shared Tabs**, app ID **6828948001**, bundle ID `com.erdabolabs.SettlingUp`. The shorter listing name was unavailable; the home-screen name remains SettlingUp. [TestFlight](https://appstoreconnect.apple.com/apps/6828948001/testflight).

## Apple setup

1. Open `SettlingUp.xcodeproj`. Select the SettlingUp target and your existing Apple Developer team. The project carries the same team identifier as the Flipbook reference; confirm it is the intended team. The proposed bundle ID is `com.erdabolabs.SettlingUp`; confirm it is available before registering. If changing it, update the target and test bundle identifiers, entitlement container identifier, and `TabStore.cloudIdentifier` consistently.
2. In Signing & Capabilities, enable **iCloud → CloudKit**, create/select `iCloud.com.erdabolabs.SettlingUp`, and enable **Push Notifications**. Background remote notifications and `CKSharingSupported` are already declared. Use automatic signing and let Xcode provision the registered capabilities. No Apple account credentials belong in this repo.
3. Build and run a signed development build on two iPhones signed into **different** iCloud accounts. iCloud must be available on both phones. Check Console/CloudKit events for setup errors. Never use the production schema for development writes.
4. Create a development tab, people, all three split modes, tax/tip, and recorded payments, and exercise sharing. Ensure the development CloudKit schema includes every attribute and relationship for `SUTab` and `SUEntry`, plus Core Data's generated record types. If using `initializeCloudKitSchema(options:)` from the debugger or a temporary development tool, run it **only in development**, never in normal production startup.
5. In CloudKit Console, inspect and deploy the verified **schema** to Production before TestFlight. Development data is not migrated by schema deployment. Do not reset or delete a container to troubleshoot a live app.
6. Create an App Store Connect record using the chosen bundle ID. Confirm display name availability, distribution region, age rating, privacy answers and support/privacy URLs. Review the bundled privacy manifest against the final binary and current App Store questions.

### Xcode reports that the capability associated with “ICLOUD” could not be determined

This occurred on Xcode 27.1 during automatic development-profile creation. The project showed the iCloud container name, but the App ID and container had not actually been registered in the Apple Developer account. Registering both and linking the container was necessary, but automatic signing still returned the same error. The workaround was to create the development profile in Apple's portal and select it explicitly in Xcode.

Both **Debug** and **Release** now use manual development signing with **SettlingUp Development** for physical-iPhone builds/archives. Distribution export re-signs the archive with the separate **Apple Distribution** identity and **SettlingUp App Store** provisioning profile. The development profile alone is not a TestFlight distribution profile. Existing project and encryption-setting edits made by the owner were retained.

A signed Debug build for `generic/platform=iOS` succeeded on October 30, 2026 using this profile. It was not installed or uploaded during signing verification.

To reproduce on another Mac if needed:

1. In Apple Developer → Certificates, Identifiers & Profiles, verify the explicit App ID `com.erdabolabs.SettlingUp` exists with iCloud/CloudKit and Push Notifications enabled. A matching name displayed locally in Xcode is not proof of registration.
2. Verify `iCloud.com.erdabolabs.SettlingUp` exists under iCloud Containers and is assigned to that App ID. Apple's container-registration form adds the `iCloud.` prefix automatically; enter `com.erdabolabs.SettlingUp` in its identifier field and verify the final identifier before registering.
3. Create an **iOS App Development** profile for SettlingUp. Select the existing Apple Development certificate and the intended registered test phone, name it **SettlingUp Development**, generate and download it. Do not revoke working certificates or delete containers to troubleshoot this error.
4. In Xcode → SettlingUp target → Signing & Capabilities → **Debug**, turn off Automatically manage signing. Open the Provisioning Profile menu → **Import Profile…**, then select the downloaded `.mobileprovision` file. Confirm Xcode displays the expected team and Apple Development certificate without warnings.
5. Select the registered physical phone and build/run. The development profile does not apply to simulators or authorize App Store distribution. A second physical tester phone must be registered and included in a development profile, or receive an approved TestFlight build.

On October 30 the owner approved creation of the Apple Distribution identity in the Mac Keychain, approved its signing-key use, and accepted Apple's updated agreement. The manually generated App Store profile bypassed the automatic-signing failure. The exported package was signature-verified and checked for Production iCloud, production APNs, the expected container, disabled debugger access, and the non-exempt-encryption declaration before upload. No private key was exported or committed.

For schema setup, Debug builds support `--enable-cloud --initialize-cloud-schema`. Use this only with a development-signed build and a signed-in simulator/device; Apple's initializer creates then removes representative development records. `--print-cloud-schema` performs a dry run instead. Neither schema-initialization path exists in Release builds. An initial server rate-limit response was retried after Apple's requested interval; schema initialization and production deployment then succeeded. Routine app launches do not initialize schema.

Remaining work is installation and real sharing validation, not re-registering the App ID/container or redeploying the same schema.

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
