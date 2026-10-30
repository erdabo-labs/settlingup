import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: UUID?
    @State private var creating = false
    @State private var settings = false
    @State private var search = ""
    private var filtered: [TabSnapshot] { store.tabs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(filtered) { tab in
                        NavigationLink(value: tab.id) { TabCard(tab: tab) }
                    }
                } header: { Text("Your tabs") } footer: {
                    Label(store.status, systemImage: store.cloudEnabled ? "icloud" : "iphone").font(.caption)
                }
            }
            .scrollContentBackground(.hidden).background(Brand.background)
            .overlay {
                if store.ready && store.tabs.isEmpty {
                    ContentUnavailableView {
                        Label("Good times. Easy splits.", systemImage: "person.2.circle")
                    } description: {
                        Text("Start a tab for dinner, a trip, or the everyday things you share.")
                    } actions: {
                        Button("Create a tab", systemImage: "plus") { creating = true }.buttonStyle(.borderedProminent)
                    }
                } else if !store.ready {
                    ContentUnavailableView("Could not open your tabs", systemImage: "externaldrive.badge.exclamationmark", description: Text(store.error ?? "Reopen the app to try again. Your saved files have been kept."))
                }
            }
            .navigationTitle("SettlingUp")
            .searchable(text: $search, prompt: "Find a tab")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
                ToolbarItem(placement: .primaryAction) { Button("New tab", systemImage: "plus") { creating = true }.disabled(!store.ready) }
            }
        } detail: {
            if let id = selection, let tab = store.tabs.first(where: { $0.id == id }) {
                TabDetailView(tab: tab)
            } else {
                ContentUnavailableView("Pick a tab", systemImage: "person.2", description: Text("Keep shared expenses and settle up together."))
                    .background(Brand.background)
            }
        }
        .font(Brand.ui())
        .sheet(isPresented: $creating) { CreateTabView { selection = $0 }.environmentObject(store) }
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
        .alert("SettlingUp needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
    }
}

struct CreateTabView: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var names = ["", ""]
    @State private var error: String?
    let created: (UUID) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("What's the occasion?") { TextField("Dinner, weekend away…", text: $name).textInputAutocapitalization(.sentences) }
                Section {
                    ForEach(names.indices, id: \.self) { index in
                        TextField("Person \(index + 1)", text: $names[index]).textContentType(.name)
                    }
                    Button("Add another person", systemImage: "person.badge.plus") { names.append("") }.disabled(names.count >= 100)
                } header: { Text("Who's in?") } footer: { Text("You can invite people through iCloud after creating the tab.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("New tab").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        do {
                            let id = try store.create(name: name, names: names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            created(id); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct TabDetailView: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var addingExpense = false
    @State private var editing: Expense?
    @State private var shared: SharedTab?
    @State private var sharing = false
    @State private var personName = ""
    @State private var addingPerson = false
    @State private var renaming = false
    @State private var tabName = ""
    @State private var deletingTab = false
    @State private var payment: SuggestedPayment?
    @State private var undoPayment: Transfer?
    @State private var removing: Expense?
    let tab: TabSnapshot
    private var current: TabSnapshot { store.tabs.first { $0.id == tab.id } ?? tab }
    private var summary: String {
        let t = current
        let payments = Settlement.smart(t).map { "\(t.person($0.from)) pays \(t.person($0.to)) \(Money.text($0.cents))" }
        return ([t.name, "Total expenses: \(Money.text(t.total))"] + (payments.isEmpty ? ["Everyone is settled up."] : payments) + ["Shared with SettlingUp"]).joined(separator: "\n")
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if geometry.size.width >= 720 && !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 24) {
                            expenses.frame(maxWidth: .infinity)
                            settlement.frame(maxWidth: .infinity)
                        }
                    } else { expenses; settlement }
                    people
                    Label(store.status, systemImage: store.cloudEnabled ? "icloud" : "iphone")
                        .font(Brand.ui(.caption)).foregroundStyle(.secondary)
                }
                .padding().frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.background(Brand.background)
        }
        .navigationTitle(current.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Invite or manage people", systemImage: "person.crop.circle.badge.plus") {
                        sharing = true
                        Task {
                            defer { sharing = false }
                            do { shared = try await store.prepareShare(tabID: tab.id) }
                            catch { store.error = error.localizedDescription }
                        }
                    }.disabled(sharing || !store.cloudEnabled)
                    ShareLink(item: summary) { Label("Send summary", systemImage: "square.and.arrow.up") }
                    Button("Add a person", systemImage: "person.badge.plus") { addingPerson = true }
                    Button("Rename tab", systemImage: "pencil") { tabName = current.name; renaming = true }
                    Button("Delete tab", systemImage: "trash", role: .destructive) { deletingTab = true }
                } label: {
                    if sharing { ProgressView() } else { Label("Share and manage", systemImage: "ellipsis.circle") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { addingExpense = true } label: {
                Label("Add expense", systemImage: "plus").font(Brand.ui().weight(.semibold)).frame(maxWidth: 520).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).padding().frame(maxWidth: .infinity).background(.bar)
        }
        .sheet(isPresented: $addingExpense) { ExpenseEditor(tab: current).environmentObject(store) }
        .sheet(item: $editing) { expense in ExpenseEditor(tab: current, original: expense).environmentObject(store) }
        .sheet(item: $shared) { CloudSharingView(shared: $0, store: store) }
        .alert("Add a person", isPresented: $addingPerson) {
            TextField("Name", text: $personName)
            Button("Cancel", role: .cancel) { personName = "" }
            Button("Add") {
                perform { try store.addPerson(personName, tabID: tab.id) }; personName = ""
            }
        }
        .alert("Rename tab", isPresented: $renaming) {
            TextField("Tab name", text: $tabName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { perform { try store.rename(tab.id, name: tabName) } }
        }
        .confirmationDialog("Delete this tab?", isPresented: $deletingTab, titleVisibility: .visible) {
            Button("Delete tab", role: .destructive) { perform { try store.deleteTab(tab.id) } }
        } message: { Text("This permanently removes the tab and its entries from your library and synced devices. Export a backup first if you want to keep it. Shared tabs must be unshared first.") }
        .confirmationDialog("Record this payment?", isPresented: Binding(get: { payment != nil }, set: { if !$0 { payment = nil } }), titleVisibility: .visible) {
            if let payment {
                Button("Record \(Money.text(payment.cents)) paid") { perform { try store.record(payment, tabID: tab.id) }; self.payment = nil }
            }
            Button("Cancel", role: .cancel) { payment = nil }
        } message: { Text("Only record money that has actually been sent. SettlingUp does not transfer money.") }
        .confirmationDialog("Remove this expense?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let removing { Button("Delete expense", role: .destructive) { perform { try store.deleteExpense(removing, tabID: tab.id) }; self.removing = nil } }
        } message: { Text("Balances will update for everyone sharing this tab. Recorded payments will remain.") }
        .confirmationDialog("Undo this recorded payment?", isPresented: Binding(get: { undoPayment != nil }, set: { if !$0 { undoPayment = nil } }), titleVisibility: .visible) {
            if let undoPayment { Button("Undo recording", role: .destructive) { perform { try store.undo(undoPayment, tabID: tab.id) }; self.undoPayment = nil } }
        } message: { Text("This only changes the record. It does not reverse a money transfer.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE TAB SO FAR").font(Brand.ui(.caption).weight(.semibold)).foregroundStyle(.secondary)
            MoneyLabel(cents: current.total, style: .largeTitle).foregroundStyle(Brand.accent)
            Text("\(current.people.count) people · \(current.expenses.count) expenses").foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var expenses: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Expenses").font(Brand.ui(.title2).weight(.semibold))
            if current.expenses.isEmpty { Text("Add the first expense. We'll handle the math.").foregroundStyle(.secondary).padding(.vertical) }
            ForEach(current.expenses) { expense in
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { Text(expense.title).fontWeight(.semibold); Spacer(); MoneyLabel(cents: expense.cents) }
                        VStack(alignment: .leading) { Text(expense.title).fontWeight(.semibold); MoneyLabel(cents: expense.cents) }
                    }
                    Text("Paid by \(current.person(expense.payer)) · \(expense.mode.rawValue) split").font(Brand.ui(.subheadline)).foregroundStyle(.secondary)
                    DisclosureGroup("Split details") {
                        ForEach(current.people.filter { expense.shares[$0.id] != nil }) { person in
                            HStack { Text(person.name); Spacer(); MoneyLabel(cents: expense.shares[person.id] ?? 0, style: .subheadline) }.padding(.vertical, 4)
                        }
                    }.font(Brand.ui(.subheadline))
                    HStack {
                        Button("Edit", systemImage: "pencil") { editing = expense }.frame(minHeight: 44)
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { removing = expense }.frame(minHeight: 44)
                    }.font(Brand.ui(.subheadline))
                }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var settlement: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settle up").font(Brand.ui(.title2).weight(.semibold))
            let suggestions = Settlement.smart(current)
            if suggestions.isEmpty {
                Label(current.expenses.isEmpty ? "No expenses yet" : "Everyone is settled up", systemImage: "checkmark.circle")
                    .foregroundStyle(.green).padding(.vertical)
            }
            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(current.person(suggestion.from)) pays \(current.person(suggestion.to))").fontWeight(.medium)
                    MoneyLabel(cents: suggestion.cents, style: .title2).foregroundStyle(Brand.accent)
                    Button("Record as paid", systemImage: "checkmark") { payment = suggestion }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
            if !current.transfers.isEmpty {
                Text("Recorded payments").font(Brand.ui(.title3)).padding(.top, 8)
                ForEach(current.transfers) { transfer in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(current.person(transfer.from)) paid \(current.person(transfer.to))")
                        MoneyLabel(cents: transfer.cents)
                        Text(transfer.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Button("Undo recording", role: .destructive) { undoPayment = transfer }.frame(minHeight: 44)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People & balances").font(Brand.ui(.title2).weight(.semibold))
            let balances = Settlement.balances(current)
            ForEach(current.people) { person in
                let balance = balances[person.id, default: 0]
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name).fontWeight(.medium)
                    Text(balance == 0 ? "Settled up" : balance > 0 ? "Gets back \(Money.text(balance))" : "Owes \(Money.text(-balance))")
                        .font(Brand.number(.subheadline)).foregroundStyle(balance > 0 ? Brand.accent : .secondary)
                }.padding(.vertical, 4).accessibilityElement(children: .combine)
            }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { store.error = error.localizedDescription }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "Dark"
    @State private var backup: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") { Picker("Theme", selection: $appearance) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0) } } }
                Section("Your data") {
                    Label(store.status, systemImage: store.cloudEnabled ? "icloud" : "iphone")
                    Text("Tabs are saved on your device. When iCloud is available, your private tabs sync and invited people can collaborate. Updates may take time to arrive.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Export complete backup", systemImage: "square.and.arrow.up") {
                        do { backup = BackupDocument(data: try store.exportBackup()); exporting = true }
                        catch { store.error = error.localizedDescription }
                    }
                    Button("Restore backup into empty library", systemImage: "square.and.arrow.down") { importing = true }.disabled(!store.tabs.isEmpty)
                    Text("Restored tabs are private copies. Invite people again after restoring. Existing website tabs are separate and are not imported automatically.").font(.caption).foregroundStyle(.secondary)
                    Text("To leave a shared tab, open its iCloud sharing controls. When an owner stops sharing, SettlingUp keeps a private copy for the owner.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Names, expenses, and recorded payments stay on your device and in your Apple iCloud account. People you invite can access the shared tab. SettlingUp does not process payments or include advertising or analytics.")
                    Text("Backups contain your tab data. Store them somewhere private.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("SettlingUp · 0.1.0 (1)").foregroundStyle(.secondary) }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "SettlingUp-backup") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try store.importBackup(Data(contentsOf: url))
                } catch { store.error = error.localizedDescription }
            }
        }
    }
}
