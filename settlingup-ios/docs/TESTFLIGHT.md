# Internal TestFlight distribution

App: **SettlingUp: Shared Tabs** (home screen: SettlingUp)

Bundle ID: `com.erdabolabs.SettlingUp` · App Store Connect ID: `6828948001`

[Open TestFlight management](https://appstoreconnect.apple.com/apps/6828948001/testflight)

## First upload — October 30, 2026

Version **0.1.0**, build **1** was uploaded successfully for **internal testing only**. Apple completed processing; the **Personal** group has **1 Tester · 1 Build**, and build 1 is **Testing**. The owner account is the sole tester. Automatic distribution of future builds is disabled. This is not a public App Store submission.

- The Apple Developer agreement was accepted by the owner.
- Development and distribution profiles were registered manually because Xcode 27.1 automatic signing failed on `ICLOUD` capability lookup.
- The owner approved a new Apple Distribution certificate; its private key is in the Mac Keychain, not in this repo. The App Store profile is **SettlingUp App Store**; the archive profile is **SettlingUp Development**.
- The exact app Core Data model initialized `CD_SUEntry` and `CD_SUTab` in CloudKit Development using the signed-in Duo simulator. The schema, including generated indexes, was deployed to Production and verified there. No existing app data or Supabase records were migrated/deleted.
- Exported signature verification passed. The signed package has Production iCloud, production APNs, the intended CloudKit container, no debugger entitlement and the declared encryption exemption. The distribution uses Apple's standard system cryptography.
- All 21 local settlement/persistence tests passed again after the schema helper and signing changes. The development-only initializer is excluded from the uploaded Release app.

## Install on your phone

Open Apple's **TestFlight** app and install **SettlingUp: Shared Tabs**. Accept the invitation for your owner account first if the app is not yet visible. Your real phone can keep **Developer Mode off**. Initial internal availability does not establish that two-account sharing is fully verified.

Use a disposable tab for first tests: create people, add an even/custom/personal expense, quit/reopen, export a backup, then invite a second iCloud account. Confirm both people see changes before depending on shared financial records. See `RELEASE.md` for the remaining acceptance checks.

## Next uploads

1. Increment `CURRENT_PROJECT_VERSION` before the next upload; build 1 is already used. Keep the bundle identifier/container stable.
2. Archive the Release configuration for generic iOS. Project archive signing uses the working manual development profile. Do not try installing an App Store export directly from Xcode as a substitute for TestFlight.
3. Re-sign/export using `method=app-store-connect`, `signingStyle=manual`, your team, `signingCertificate=Apple Distribution`, and `provisioningProfiles={com.erdabolabs.SettlingUp: SettlingUp App Store}`. Set `iCloudContainerEnvironment=Production` and `testFlightInternalTestingOnly=true` for a personal internal beta. Local export and upload can use separate export-options plists, with `destination=export` or `destination=upload`.
4. This working copy's ignored `build/` directory contains the signed archive, verified `.ipa`, export-options examples and upload output. Provisioning files and private keys are not source files and must not be committed.
5. Validate the signed package and upload only when authorized. Wait for processing, then assign the processed build to the intended internal group. This group is manually managed so future builds are not automatically distributed.

External testing/public release needs its own distribution choice and review. Internal-only builds cannot later be used for external testing or App Store release. Public privacy/support pages, broader accessibility/device QA and multi-account lifecycle checks remain release work.
