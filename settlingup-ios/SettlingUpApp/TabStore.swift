import CloudKit
import Combine
import CoreData

@objc(SUTab)
final class SUTab: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var created: Date?
    @NSManaged var entries: Set<SUEntry>?
}

@objc(SUEntry)
final class SUEntry: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var kind: String?
    @NSManaged var payload: Data?
    @NSManaged var tab: SUTab?
}

struct SharedTab: Identifiable {
    let id = UUID()
    let tabID: UUID
    let snapshot: TabSnapshot
    let share: CKShare
    let container: CKContainer
    let store: NSPersistentStore
}

@MainActor
final class TabStore: ObservableObject {
    static let cloudIdentifier = "iCloud.com.erdabolabs.SettlingUp"
    private static let managedModel = model()
    @Published private(set) var tabs: [TabSnapshot] = []
    @Published var error: String?
    @Published private(set) var status = "Opening your tabs…"
    @Published private(set) var ready = false
    @Published private(set) var dataReadable = true
    @Published private(set) var lastSync: Date?
    let container: NSPersistentCloudKitContainer
    let cloudEnabled: Bool
    private var privateStore: NSPersistentStore?
    private var sharedStore: NSPersistentStore?
    private var observers: [NSObjectProtocol] = []
    private var objects: [UUID: SUTab] = [:]
    var context: NSManagedObjectContext { container.viewContext }

    init(directory: URL? = nil, cloud: Bool = true, inMemory: Bool = false) {
        cloudEnabled = cloud && !inMemory
        container = NSPersistentCloudKitContainer(name: "SettlingUp", managedObjectModel: Self.managedModel)
        do {
            let folder = directory ?? NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("SettlingUp", isDirectory: true)
            if !inMemory { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            let local = NSPersistentStoreDescription(url: inMemory ? URL(fileURLWithPath: "/dev/null") : folder.appendingPathComponent("Private.sqlite"))
            local.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            local.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            local.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if cloudEnabled {
                local.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudIdentifier)
                local.cloudKitContainerOptions?.databaseScope = .private
                let shared = NSPersistentStoreDescription(url: folder.appendingPathComponent("Shared.sqlite"))
                shared.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                shared.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                shared.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudIdentifier)
                shared.cloudKitContainerOptions?.databaseScope = .shared
                container.persistentStoreDescriptions = [local, shared]
            } else { container.persistentStoreDescriptions = [local] }
            var failures: [String] = []
            container.loadPersistentStores { _, error in
                if let error { failures.append(error.localizedDescription) }
            }
            guard failures.isEmpty else { throw TabError.invalid(failures.joined(separator: "\n")) }
            privateStore = container.persistentStoreCoordinator.persistentStores.first { $0.url == local.url }
            sharedStore = container.persistentStoreCoordinator.persistentStores.first { $0.url?.lastPathComponent == "Shared.sqlite" }
            context.automaticallyMergesChangesFromParent = true
            // Do not silently overwrite an expense edited on another device while a form is open.
            context.mergePolicy = NSErrorMergePolicy
            ready = true
            status = cloudEnabled ? "Saved on device · iCloud updates automatically" : "Saved on this device"
            reload()
            observeChanges()
        } catch {
            self.error = "Could not open your saved tabs. Your files have been kept. \(error.localizedDescription)"
            status = "Storage unavailable"
        }
    }

    private static func model() -> NSManagedObjectModel {
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let value = NSAttributeDescription(); value.name = name; value.attributeType = type; value.isOptional = true
            return value
        }
        let tab = NSEntityDescription(); tab.name = "SUTab"; tab.managedObjectClassName = NSStringFromClass(SUTab.self)
        let entry = NSEntityDescription(); entry.name = "SUEntry"; entry.managedObjectClassName = NSStringFromClass(SUEntry.self)
        let children = NSRelationshipDescription(); children.name = "entries"; children.destinationEntity = entry
        children.minCount = 0; children.maxCount = 0; children.isOptional = true; children.deleteRule = .cascadeDeleteRule
        let parent = NSRelationshipDescription(); parent.name = "tab"; parent.destinationEntity = tab
        parent.minCount = 0; parent.maxCount = 1; parent.isOptional = true; parent.deleteRule = .nullifyDeleteRule
        children.inverseRelationship = parent; parent.inverseRelationship = children
        tab.properties = [attribute("id", .UUIDAttributeType), attribute("name", .stringAttributeType), attribute("created", .dateAttributeType), children]
        entry.properties = [attribute("id", .UUIDAttributeType), attribute("kind", .stringAttributeType), attribute("payload", .binaryDataAttributeType), parent]
        let model = NSManagedObjectModel(); model.entities = [tab, entry]
        return model
    }

    private func observeChanges() {
        observers.append(NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        if cloudEnabled {
            observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: .main) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if let failure = event.error {
                        self.status = "Saved on device · iCloud needs attention"
                        self.error = "iCloud could not finish syncing. Local changes are saved and will retry. \(failure.localizedDescription)"
                    } else if let end = event.endDate, event.succeeded {
                        self.lastSync = end
                        self.status = "Saved on device · Last iCloud activity \(end.formatted(date: .omitted, time: .shortened))"
                        self.reload()
                    }
                }
            })
        }
    }

    func reload() {
        guard ready else { return }
        do {
            let request = NSFetchRequest<SUTab>(entityName: "SUTab")
            request.sortDescriptors = [NSSortDescriptor(key: "created", ascending: false)]
            let records = try context.fetch(request)
            var next: [TabSnapshot] = [], mapping: [UUID: SUTab] = [:]
            for record in records {
                guard let id = record.id, let name = record.name, let created = record.created else {
                    throw TabError.invalid("A tab is incomplete. Allow iCloud to finish syncing, then reopen the app.")
                }
                var snapshot = TabSnapshot(id: id, name: name, created: created)
                for entry in record.entries ?? [] {
                    guard let data = entry.payload else { throw TabError.invalid("An entry is incomplete. Its saved data has been kept.") }
                    let decoder = JSONDecoder()
                    switch entry.kind {
                    case "person": snapshot.people.append(try decoder.decode(Person.self, from: data))
                    case "expense": snapshot.expenses.append(try decoder.decode(Expense.self, from: data))
                    case "transfer":
                        let transfer = try decoder.decode(Transfer.self, from: data)
                        if let index = snapshot.transfers.firstIndex(where: { $0.id == transfer.id }) {
                            let existing = snapshot.transfers[index]
                            guard existing.from == transfer.from, existing.to == transfer.to, existing.cents == transfer.cents else {
                                throw TabError.invalid("Conflicting payment records were found. Your saved data has been kept.")
                            }
                            if transfer.date < existing.date { snapshot.transfers[index] = transfer }
                        } else { snapshot.transfers.append(transfer) }
                    default: throw TabError.invalid("This tab needs a newer version of SettlingUp.")
                    }
                }
                snapshot.people.sort { $0.id.uuidString < $1.id.uuidString }
                snapshot.expenses.sort { $0.date > $1.date }
                snapshot.transfers.sort { $0.date > $1.date }
                try snapshot.validate()
                guard mapping[id] == nil else { throw TabError.invalid("Duplicate tab identifiers were found. Your saved data has been kept.") }
                mapping[id] = record; next.append(snapshot)
            }
            objects = mapping; tabs = next; dataReadable = true
        } catch { dataReadable = false; self.error = error.localizedDescription }
    }

    func refresh() {
        guard ready, !context.hasChanges else { return }
        context.refreshAllObjects()
        reload()
    }

    private func commit() throws {
        do { try context.save(); reload() }
        catch { context.rollback(); reload(); throw error }
    }

    private func tabObject(_ id: UUID) throws -> SUTab {
        guard ready, dataReadable, let tab = objects[id], !tab.isDeleted else { throw TabError.invalid("This tab is unavailable or is still syncing. Reopen it before making changes.") }
        guard !cloudEnabled || container.canUpdateRecord(forManagedObjectWith: tab.objectID) else {
            throw TabError.invalid("You have read-only access to this tab.")
        }
        return tab
    }

    private func insert<T: Encodable>(_ value: T, id: UUID, kind: String, tab: SUTab) throws {
        let data = try JSONEncoder().encode(value)
        let entry = SUEntry(context: context)
        if let store = tab.objectID.persistentStore { context.assign(entry, to: store) }
        entry.id = id; entry.kind = kind; entry.payload = data; entry.tab = tab
    }

    @discardableResult
    func create(name: String, names: [String]) throws -> UUID {
        guard ready, dataReadable, let privateStore else { throw TabError.invalid("Storage is not ready.") }
        let people = names.map { Person(name: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let snapshot = TabSnapshot(name: name.trimmingCharacters(in: .whitespacesAndNewlines), people: people)
        try snapshot.validate()
        guard people.count >= 2 else { throw TabError.invalid("Add at least two people.") }
        let tab = SUTab(context: context); context.assign(tab, to: privateStore)
        tab.id = snapshot.id; tab.name = snapshot.name; tab.created = snapshot.created
        do {
            for person in people { try insert(person, id: person.id, kind: "person", tab: tab) }
            try commit(); return snapshot.id
        } catch { context.rollback(); throw error }
    }

    func addPerson(_ name: String, tabID: UUID) throws {
        let tab = try tabObject(tabID)
        let person = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard var snapshot = tabs.first(where: { $0.id == tabID }) else { return }
        snapshot.people.append(person); try snapshot.validate()
        try insert(person, id: person.id, kind: "person", tab: tab); try commit()
    }

    func save(_ expense: Expense, tabID: UUID, original: Expense? = nil) throws {
        let tab = try tabObject(tabID)
        guard let snapshot = tabs.first(where: { $0.id == tabID }) else { return }
        try expense.validate(people: Set(snapshot.people.map(\.id)))
        if let original {
            guard let entry = tab.entries?.first(where: { $0.id == original.id && $0.kind == "expense" }),
                  let data = entry.payload, try JSONDecoder().decode(Expense.self, from: data) == original else {
                throw TabError.invalid("This expense changed on another device. Close this form and reopen it before editing.")
            }
            entry.payload = try JSONEncoder().encode(expense)
        } else {
            guard snapshot.expenses.count < 10_000 else { throw TabError.invalid("This tab has reached its expense limit.") }
            try insert(expense, id: expense.id, kind: "expense", tab: tab)
        }
        try commit()
    }

    func deleteExpense(_ expense: Expense, tabID: UUID) throws {
        let tab = try tabObject(tabID)
        guard let entry = tab.entries?.first(where: { $0.id == expense.id && $0.kind == "expense" }),
              let data = entry.payload, try JSONDecoder().decode(Expense.self, from: data) == expense else {
            throw TabError.invalid("This expense changed. Reopen it before deleting.")
        }
        context.delete(entry); try commit()
    }

    func record(_ payment: SuggestedPayment, tabID: UUID) throws {
        let tab = try tabObject(tabID)
        guard let snapshot = tabs.first(where: { $0.id == tabID }), Settlement.smart(snapshot).contains(payment) else {
            throw TabError.invalid("The balances changed. Review the updated payment before recording it.")
        }
        guard snapshot.transfers.count < 10_000 else { throw TabError.invalid("This tab has reached its payment limit.") }
        let transfer = Transfer(id: Settlement.paymentID(payment, tab: snapshot), from: payment.from, to: payment.to, cents: payment.cents)
        try insert(transfer, id: transfer.id, kind: "transfer", tab: tab); try commit()
    }

    func undo(_ transfer: Transfer, tabID: UUID) throws {
        let tab = try tabObject(tabID)
        for entry in tab.entries ?? [] where entry.id == transfer.id && entry.kind == "transfer" { context.delete(entry) }
        try commit()
    }

    func prepareShare(tabID: UUID) async throws -> SharedTab {
        guard cloudEnabled else { throw TabError.invalid("iCloud sharing is unavailable in local preview mode.") }
        let tab = try tabObject(tabID)
        guard let snapshot = tabs.first(where: { $0.id == tabID }) else { throw TabError.invalid("This tab is unavailable.") }
        let cloud = CKContainer(identifier: Self.cloudIdentifier)
        guard try await cloud.accountStatus() == .available else {
            throw TabError.invalid("Sign in to iCloud in Settings to invite people.")
        }
        guard let store = tab.objectID.persistentStore else { throw TabError.invalid("Save the tab before sharing.") }
        if let share = try container.fetchShares(matching: [tab.objectID])[tab.objectID] {
            return SharedTab(tabID: tabID, snapshot: snapshot, share: share, container: cloud, store: store)
        }
        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            container.share([tab], to: nil) { _, share, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let share { continuation.resume(returning: share) }
                else { continuation.resume(throwing: TabError.invalid("Could not create an iCloud invitation.")) }
            }
        }
        share[CKShare.SystemFieldKey.title] = (tab.name ?? "SettlingUp tab") as CKRecordValue
        share.publicPermission = .none
        return SharedTab(tabID: tabID, snapshot: snapshot, share: share, container: cloud, store: store)
    }

    func persist(_ share: CKShare, store: NSPersistentStore) {
        container.persistUpdatedShare(share, in: store) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.error = "Could not update sharing permissions: \(error.localizedDescription)" }
                self?.reload()
            }
        }
    }

    func accept(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == Self.cloudIdentifier else { error = "This invitation belongs to another app."; return }
        guard ready, let sharedStore else { error = "iCloud sharing is not ready. Reopen the invitation after configuring iCloud."; return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.error = "Could not join this tab: \(error.localizedDescription)" }
                else { self?.status = "Invitation accepted · Waiting for iCloud to download the tab"; self?.reload() }
            }
        }
    }

    func exportBackup() throws -> Data {
        guard ready, dataReadable else { throw TabError.invalid("Some saved data is unavailable or still syncing. Try again after iCloud finishes.") }
        let backup = Backup(version: 1, tabs: tabs)
        return try JSONEncoder().encode(backup)
    }

    func importBackup(_ data: Data) throws {
        guard ready, dataReadable, let privateStore else { throw TabError.invalid("Storage is unavailable.") }
        guard tabs.isEmpty else { throw TabError.invalid("Restore requires an empty library to avoid duplicating shared records.") }
        guard data.count <= 25_000_000 else { throw TabError.invalid("This backup is too large.") }
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        guard backup.version == 1, backup.tabs.count <= 1_000, Set(backup.tabs.map(\.id)).count == backup.tabs.count else {
            throw TabError.invalid("Unsupported backup version or duplicate tabs.")
        }
        for snapshot in backup.tabs { try snapshot.validate() }
        do {
            for source in backup.tabs {
                let snapshot = source.privateCopy()
                let tab = SUTab(context: context); context.assign(tab, to: privateStore)
                tab.id = snapshot.id; tab.name = snapshot.name; tab.created = snapshot.created
                for person in snapshot.people { try insert(person, id: person.id, kind: "person", tab: tab) }
                for expense in snapshot.expenses { try insert(expense, id: expense.id, kind: "expense", tab: tab) }
                for transfer in snapshot.transfers { try insert(transfer, id: transfer.id, kind: "transfer", tab: tab) }
            }
            try commit()
        } catch { context.rollback(); reload(); throw error }
    }

    func rename(_ id: UUID, name: String) throws {
        let tab = try tabObject(id)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw TabError.invalid("Use a tab name between 1 and 100 characters.") }
        tab.name = name; try commit()
    }

    func deleteTab(_ id: UUID) throws {
        let tab = try tabObject(id)
        guard tab.objectID.persistentStore == privateStore else {
            throw TabError.invalid("Use iCloud sharing controls to leave a tab someone shared with you.")
        }
        if cloudEnabled, try container.fetchShares(matching: [tab.objectID])[tab.objectID] != nil {
            throw TabError.invalid("Stop sharing this tab using the iCloud sharing controls before deleting it. A private copy will be kept when you stop sharing.")
        }
        context.delete(tab); try commit()
    }

    func stoppedSharing(_ shared: SharedTab) {
        do {
            if shared.store == privateStore, let privateStore {
                let source = tabs.first(where: { $0.id == shared.tabID }) ?? shared.snapshot
                let snapshot = source.privateCopy()
                // CloudKit purges the shared graph when sharing stops. Keep an independent owner copy first.
                let copy = SUTab(context: context); context.assign(copy, to: privateStore)
                copy.id = snapshot.id; copy.name = String(snapshot.name.prefix(85)) + " (Private copy)"; copy.created = snapshot.created
                for person in snapshot.people { try insert(person, id: person.id, kind: "person", tab: copy) }
                for expense in snapshot.expenses { try insert(expense, id: expense.id, kind: "expense", tab: copy) }
                for transfer in snapshot.transfers { try insert(transfer, id: transfer.id, kind: "transfer", tab: copy) }
                try commit()
            }
            container.purgeObjectsAndRecordsInZone(with: shared.share.recordID.zoneID, in: shared.store) { [weak self] _, error in
                Task { @MainActor in
                    if let error { self?.error = "Sharing ended, but cleanup could not finish. Reopen the app. \(error.localizedDescription)" }
                    self?.refresh()
                }
            }
        } catch { context.rollback(); self.error = "Could not preserve a private copy. Export a backup before reopening the app. \(error.localizedDescription)" }
    }
}

struct Backup: Codable { var version: Int; var tabs: [TabSnapshot] }
