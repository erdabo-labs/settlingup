import SwiftUI
import CloudKit

@main
struct SettlingUpApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: TabStore
    @AppStorage("appearance") private var appearance = "Dark"

    init() {
        let testing = ProcessInfo.processInfo.environment["SETTLINGUP_TESTING"] == "1" || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let preview = ProcessInfo.processInfo.arguments.contains("--sample-data")
        #if DEBUG
        let sharingSchema = ProcessInfo.processInfo.arguments.contains("--initialize-sharing-schema")
        #else
        let sharingSchema = false
        #endif
        #if targetEnvironment(simulator)
        let local = !ProcessInfo.processInfo.arguments.contains("--enable-cloud")
        #else
        let local = ProcessInfo.processInfo.arguments.contains("--local-only")
        #endif
        var diagnosticDirectory: URL?
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cloud-diagnostic") {
            diagnosticDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SettlingUp-CloudDiagnostic")
        }
        #endif
        let store = TabStore(directory: diagnosticDirectory, cloud: !testing && !preview && !local && !sharingSchema, inMemory: testing || preview || sharingSchema)
        #if DEBUG
        if sharingSchema {
            Task {
                do {
                    let database = CKContainer(identifier: TabStore.cloudIdentifier).privateCloudDatabase
                    let zone = try await database.save(CKRecordZone(zoneName: "SettlingUpDevelopmentSharingDiagnostic"))
                    let share = CKShare(recordZoneID: zone.zoneID)
                    share.publicPermission = .none
                    let saved = try await database.save(share) as? CKShare
                    print("SettlingUp sharing schema diagnostic saved; URL available: \(saved?.url != nil)")
                } catch { print("SettlingUp sharing schema diagnostic failed: " + TabStore.describe(error)) }
            }
        }
        if diagnosticDirectory != nil && store.tabs.isEmpty {
            do {
                let id = try store.create(name: "Cloud sync diagnostic", names: ["Test A", "Test B"])
                let people = store.tabs.first!.people
                try store.save(Expense(title: "Diagnostic expense", payer: people[0].id, cents: 1000,
                                       shares: try Settlement.even(cents: 1000, people: people.map(\.id)), mode: .even), tabID: id)
                print("SettlingUp diagnostic fixture saved in isolated local store.")
            } catch { print("SettlingUp diagnostic save failed: \(error)") }
        }
        let initializeSchema = ProcessInfo.processInfo.arguments.contains("--initialize-cloud-schema")
        if initializeSchema || ProcessInfo.processInfo.arguments.contains("--print-cloud-schema") {
            do {
                try store.container.initializeCloudKitSchema(options: initializeSchema ? [.printSchema] : [.dryRun, .printSchema])
                print(initializeSchema ? "SettlingUp development CloudKit schema initialized." : "SettlingUp CloudKit schema validation completed (dry run; no records uploaded).")
            } catch { print("SettlingUp CloudKit schema validation failed: \(error)") }
        }
        #endif
        if preview {
            do {
                let id = try store.create(name: "Mountain weekend", names: ["Erik", "Sam", "Alex"])
                let people = store.tabs[0].people
                let shares = try Settlement.even(cents: 12840, people: people.map(\.id))
                try store.save(Expense(title: "Dinner after the hike", payer: people[0].id, cents: 12840, shares: shares, mode: .even), tabID: id)
            } catch { store.error = error.localizedDescription }
        }
        _store = StateObject(wrappedValue: store)
        AppDelegate.store = store
    }

    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store)
                .tint(Brand.accent)
                .preferredColorScheme(appearance == "System" ? nil : appearance == "Light" ? .light : .dark)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var store: TabStore?
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Self.store?.accept(metadata)
    }
}

@MainActor
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata { AppDelegate.store?.accept(metadata) }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        AppDelegate.store?.accept(metadata)
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let shared: SharedTab
    let store: TabStore
    func makeCoordinator() -> Coordinator { Coordinator(shared: shared, store: store) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: shared.share, container: shared.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let shared: SharedTab
        let store: TabStore
        init(shared: SharedTab, store: TabStore) { self.shared = shared; self.store = store }
        func itemTitle(for controller: UICloudSharingController) -> String? { shared.share[CKShare.SystemFieldKey.title] as? String }
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            store.error = "Could not save the iCloud invitation: \(TabStore.describe(error))"
        }
        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            if let share = controller.share { store.persist(share, store: shared.store) }
        }
        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            store.stoppedSharing(shared)
        }
    }
}
