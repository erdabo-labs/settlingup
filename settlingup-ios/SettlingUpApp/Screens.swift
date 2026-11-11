import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: UUID?
    @State private var tabName = ""
    @State private var creating = false
    @State private var settings = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let selected, let tab = store.tabs.first(where: { $0.id == selected }) {
                    TabDetailView(tab: tab) { self.selected = nil }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            BrandHeader { selected = nil }
                            StepProgress(step: 0)
                            VStack(alignment: .center, spacing: 8) {
                                Text("Split expenses.").font(Brand.ui(.title, weight: .heavy))
                                Text("Settle up fairly.").font(Brand.ui(.title, weight: .heavy)).foregroundStyle(Brand.accent)
                                Text("Shared tabs with your friends. Saved on your iPhone and shared through iCloud.").font(Brand.ui(.subheadline)).foregroundStyle(.secondary)
                                Text("✈️ Trips    🍕 Dinners    🏠 Bills    🎉 Events").font(Brand.ui(.caption)).padding(.top, 6)
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 24)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TAB NAME").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                                TextField("Summer Trip 2026", text: $tabName).font(Brand.ui(.title3)).webInput()
                            }.webCard()
                            Button {
                                if tabName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "Give your tab a name first." }
                                else { error = nil; creating = true }
                            } label: { Text("Add people →").frame(maxWidth: .infinity) }.buttonStyle(WebButton()).disabled(!store.ready)
                            if let error { Text(error).foregroundStyle(.red) }
                            if !store.tabs.isEmpty {
                                Text("YOUR TABS").font(Brand.ui(.caption, weight: .semibold)).foregroundStyle(.secondary)
                                ForEach(store.tabs) { tab in
                                    TabCard(tab: tab) { selected = tab.id }.webCard()
                                }
                            }
                            DisclosureGroup("Try a demo") {
                                VStack(spacing: 10) {
                                    ForEach(DemoScenario.all) { demo in
                                        Button {
                                            do { selected = try store.createDemo(demo) }
                                            catch { self.error = error.localizedDescription }
                                        } label: {
                                            HStack {
                                                Text(demo.icon).font(.title2)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(demo.title).font(Brand.ui(.subheadline, weight: .semibold))
                                                    Text("\(demo.people.count) people · \(demo.expenses.count) expenses").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                                                }
                                                Spacer(); Image(systemName: "arrow.right")
                                            }.webCard()
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.top, 10)
                            }
                            Label(store.status, systemImage: store.cloudEnabled ? "icloud" : "iphone").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                            Button("Settings & backup", systemImage: "gearshape") { settings = true }.frame(minHeight: 44)
                        }.padding(16).frame(maxWidth: 480).frame(maxWidth: .infinity)
                    }.background(Brand.background)
                }
            }.toolbar(.hidden, for: .navigationBar)
        }.font(Brand.ui())
        .sheet(isPresented: $creating) { CreateTabView(initialName: tabName) { selected = $0; tabName = "" }.environmentObject(store) }
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
        .safeAreaInset(edge: .bottom) {
            if let error = store.error {
                HStack(alignment: .top) {
                    Text(error).font(Brand.ui(.caption))
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") { store.error = nil }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.padding().background(Brand.background).overlay(alignment: .top) { Divider() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
    }
}

struct CreateTabView: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.dismiss) private var dismiss
    let initialName: String
    let created: (UUID) -> Void
    @State private var names: [String] = []
    @State private var newName = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BrandHeader { dismiss() }
                    StepProgress(step: 1)
                    Text("Who's in?").font(Brand.ui(.largeTitle, weight: .bold))
                    Text("Add everyone — including yourself.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PEOPLE ON THIS TAB").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                        ForEach(names.indices, id: \.self) { index in
                            HStack {
                                TextField("Name", text: $names[index]).webInput()
                                Button("Remove", systemImage: "xmark") { names.remove(at: index) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                            }
                        }
                        HStack {
                            TextField("Add a name…", text: $newName).webInput().onSubmit(add)
                            Button("+ Add", action: add).buttonStyle(WebButton(primary: false))
                        }
                    }.webCard()
                    if let error { Text(error).foregroundStyle(.red).font(Brand.ui(.subheadline)) }
                    HStack {
                        Button("← Back") { dismiss() }.buttonStyle(WebButton(primary: false))
                        Button {
                            do {
                                var people = names
                                if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { people.append(newName) }
                                let id = try store.create(name: initialName, names: people)
                                created(id); dismiss()
                            } catch { self.error = error.localizedDescription }
                        } label: { Text("Add expenses →").frame(maxWidth: .infinity) }.buttonStyle(WebButton())
                    }
                }.padding(16).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(Brand.background).toolbar(.hidden, for: .navigationBar)
        }.font(Brand.ui())
    }
    private func add() {
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard !names.contains(where: { $0.lowercased() == value.lowercased() }) else { error = "That name is already in the list."; return }
        names.append(value); newName = ""; error = nil
    }
}

struct TabDetailView: View {
    @EnvironmentObject private var store: TabStore
    let tab: TabSnapshot
    let home: () -> Void
    @State private var step = 2
    @State private var direct = false
    @State private var editing: Expense?
    @State private var removing: Expense?
    @State private var shared: SharedTab?
    @State private var sharing = false
    @State private var identity = ""
    @State private var pickingIdentity = false
    @State private var newName = ""
    @State private var renamedPerson: Person?
    @State private var renameText = ""
    @State private var removedPerson: Person?
    @State private var renameTab = false
    @State private var error: String?
    private var current: TabSnapshot { store.tabs.first { $0.id == tab.id } ?? tab }
    private var payments: [SuggestedPayment] { Settlement.displayedPayments(current, direct: direct) }
    private func name(_ id: UUID) -> String { identity == id.uuidString ? "You" : current.person(id) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BrandHeader(home: home).id("top")
                    StepProgress(step: step)
                    HStack {
                        Button { renameText = current.name; renameTab = true } label: {
                            Text(current.name).font(Brand.ui(.title, weight: .bold)).foregroundStyle(.primary)
                        }.buttonStyle(.plain).accessibilityLabel("Rename \(current.name)")
                        Spacer()
                        Button { pickingIdentity = true } label: {
                            Label(identity.isEmpty ? "Who are you?" : name(UUID(uuidString: identity) ?? UUID()), systemImage: "person.crop.circle")
                                .font(Brand.ui(.caption)).padding(8).background(Brand.accent.opacity(0.10), in: Capsule())
                        }
                    }
                    if current.name.hasPrefix("DEMO: ") {
                        Text("🎭 This is a demo tab — edit freely, or load a fresh one from the home screen.").font(Brand.ui(.caption)).webCard()
                    }
                    if let error { Text(error).foregroundStyle(.red).font(Brand.ui(.subheadline)) }
                    if step == 1 { peopleEditor }
                    else if step == 2 {
                        Text("Add expenses").foregroundStyle(.secondary)
                        expenses
                        ExpenseEditor(tab: current, inline: true).environmentObject(store)
                    } else { settlement }
                    navigation
                    Label(store.status, systemImage: store.cloudEnabled ? "icloud" : "iphone").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(Brand.background)
                .onChange(of: step) { _, _ in proxy.scrollTo("top", anchor: .top) }
        }.onAppear { identity = UserDefaults.standard.string(forKey: "identity-\(tab.id)") ?? "" }
        .sheet(item: $editing) { ExpenseEditor(tab: current, original: $0).environmentObject(store) }
        .sheet(item: $shared) { CloudSharingView(shared: $0, store: store) }
        .sheet(isPresented: $pickingIdentity) { identityPicker }
        .alert("Rename tab", isPresented: $renameTab) {
            TextField("Tab name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { perform { try store.rename(tab.id, name: renameText) } }
        }
        .alert("Rename person", isPresented: Binding(get: { renamedPerson != nil }, set: { if !$0 { renamedPerson = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamedPerson = nil }
            Button("Save") { if let person = renamedPerson { perform { try store.renamePerson(person, name: renameText, tabID: tab.id) } }; renamedPerson = nil }
        }
        .confirmationDialog("Remove this expense?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let removing { Button("Delete expense", role: .destructive) { perform { try store.deleteExpense(removing, tabID: tab.id) }; self.removing = nil } }
        }
        .confirmationDialog("Remove \(removedPerson?.name ?? "person")?", isPresented: Binding(get: { removedPerson != nil }, set: { if !$0 { removedPerson = nil } }), titleVisibility: .visible) {
            if let person = removedPerson {
                Button("Remove person and related entries", role: .destructive) {
                    perform { try store.removePerson(person, tabID: tab.id) }
                    if identity == person.id.uuidString { setIdentity("") }
                    removedPerson = nil
                }
            }
        } message: {
            let count = current.expenses.filter { $0.payer == removedPerson?.id || $0.shares.keys.contains(removedPerson?.id ?? UUID()) }.count
            Text("This also deletes \(count) expenses involving this person and their recorded payments. This cannot be undone.")
        }
    }
    private var peopleEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Who's in?").font(Brand.ui(.title2, weight: .bold))
            Text("Add everyone — including yourself.").foregroundStyle(.secondary)
            ForEach(current.people) { person in
                HStack {
                    Text(name(person.id)); Spacer()
                    Button("Rename", systemImage: "pencil") { renameText = person.name; renamedPerson = person }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                    Button("Remove", systemImage: "xmark", role: .destructive) { removedPerson = person }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
            }
            HStack {
                TextField("Add a name…", text: $newName).webInput()
                Button("+ Add") { perform { try store.addPerson(newName, tabID: tab.id); newName = "" } }.buttonStyle(WebButton(primary: false))
            }
        }.webCard()
    }
    private var expenses: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !current.expenses.isEmpty {
                HStack { Text("\(current.expenses.count) EXPENSES").font(Brand.ui(.caption)); Spacer(); MoneyLabel(cents: current.total).foregroundStyle(Brand.accent) }
            }
            ForEach(current.expenses) { expense in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) { Text(expense.title).font(Brand.ui(.subheadline, weight: .semibold)); Spacer(); MoneyLabel(cents: expense.cents) }
                    HStack {
                        Text("\(name(expense.payer)) paid").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit", systemImage: "pencil") { editing = expense }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                        Button("Delete", systemImage: "trash", role: .destructive) { removing = expense }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                    DisclosureGroup("\(expense.mode.rawValue) · \(expense.shares.count) \(expense.shares.count == 1 ? "person" : "people")") {
                        ForEach(current.people.filter { expense.shares[$0.id] != nil }) { person in
                            HStack { Text(name(person.id)); Spacer(); MoneyLabel(cents: expense.shares[person.id] ?? 0, style: .subheadline) }.padding(.vertical, 4)
                        }
                    }.font(Brand.ui(.subheadline))
                }.webCard()
            }
        }
    }
    private var settlement: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("🎉   ✨   🙌   💸   🤝").font(.title2).frame(maxWidth: .infinity)
            Text("tap any payment to mark it done").font(Brand.ui(.subheadline)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            HStack {
                stat("Total", value: Money.text(current.total))
                stat("Expenses", value: String(current.expenses.count))
                stat("People", value: String(current.people.count))
            }.webCard()
            HStack {
                Text("Who pays who").font(Brand.ui(.title3, weight: .semibold))
                Spacer()
                Text("\(payments.count)").font(Brand.number(.caption)).padding(6).background(Brand.accent.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 4) {
                Button("Smart") { direct = false }.buttonStyle(WebSegment(selected: !direct))
                Button("Direct") { direct = true }.buttonStyle(WebSegment(selected: direct))
            }.accessibilityElement(children: .contain).accessibilityLabel("Settlement strategy")
            DisclosureGroup {
                Text("If Alex owes Sam $25 and Sam owes Jo $25, Smart suggests Alex pays Jo $25. Direct keeps both payments. Both settle the original expenses. Paid cards stay visible so you can mark or unmark them.")
                    .font(Brand.ui(.subheadline)).padding(.top, 8)
            } label: { Text(direct ? "Direct — settle with each person individually." : "Smart — reduces the number of transfers.").font(Brand.ui(.subheadline)) }
            if payments.isEmpty { Text("🎉 Everyone is settled — nothing to pay!").foregroundStyle(.green).webCard() }
            ForEach(payments) { payment in paymentCard(payment) }
            let unlisted = current.transfers.filter { transfer in !payments.contains { $0.from == transfer.from && $0.to == transfer.to && abs($0.cents - transfer.cents) <= 1 } }
            if !unlisted.isEmpty {
                DisclosureGroup("Other recorded payments") {
                    Text("These payments were recorded before the expenses or strategy changed.").font(Brand.ui(.caption))
                    ForEach(unlisted) { transfer in
                        HStack {
                            Text("\(name(transfer.from)) → \(name(transfer.to))"); Spacer(); MoneyLabel(cents: transfer.cents, style: .caption)
                            Button("Undo") { perform { try store.undo(transfer, tabID: tab.id) } }.frame(minHeight: 44)
                        }.font(Brand.ui(.caption))
                    }
                }
            }
            Divider()
            Text("INDIVIDUAL BREAKDOWN").font(Brand.ui(.caption, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(current.people.sorted { ($0.id.uuidString == identity ? 0 : 1) < ($1.id.uuidString == identity ? 0 : 1) }) { person in
                PersonBreakdown(tab: current, person: person, isMe: person.id.uuidString == identity, payments: payments)
            }
        }
    }
    private func stat(_ label: String, value: String) -> some View {
        VStack(spacing: 6) { Text(value).font(Brand.number(.subheadline)).foregroundStyle(Brand.accent); Text(label).font(Brand.ui(.caption)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
    private func paymentCard(_ payment: SuggestedPayment) -> some View {
        let marked = Settlement.markedPayment(payment, in: current)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) { Text(name(payment.from)).font(Brand.ui(.subheadline, weight: .semibold)); Text("pays").foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "arrow.right").foregroundStyle(.secondary); Spacer()
                VStack(alignment: .trailing) { Text(name(payment.to)).font(Brand.ui(.subheadline, weight: .semibold)); Text("receives").foregroundStyle(.secondary) }
            }.font(Brand.ui(.subheadline))
            HStack {
                MoneyLabel(cents: payment.cents, style: .title2).foregroundStyle(marked == nil ? Brand.accent : .green).strikethrough(marked != nil)
                Spacer()
                Button(marked == nil ? "Mark paid" : "✓ Paid · Undo") {
                    perform {
                        if let marked { try store.undo(marked, tabID: tab.id) }
                        else { try store.record(payment, tabID: tab.id) }
                    }
                }.buttonStyle(WebButton(primary: false))
            }
        }.webCard().opacity(marked == nil ? 1 : 0.65)
    }
    private var navigation: some View {
        VStack(spacing: 12) {
            Button { share() } label: {
                HStack { if sharing { ProgressView() }; Label("Share this tab", systemImage: "link").frame(maxWidth: .infinity) }
            }.buttonStyle(WebButton(primary: false)).disabled(sharing || !store.cloudEnabled)
            HStack {
                Button(step == 3 ? "← Edit expenses" : "← Back") { step = step == 3 ? 2 : step == 2 ? 1 : 1 }.buttonStyle(WebButton(primary: false))
                if step < 3 {
                    Button {
                        if current.people.count < 2 { error = "Add at least two people first." }
                        else if step == 2 && current.expenses.isEmpty { error = "Add at least one expense first." }
                        else { error = nil; step += 1 }
                    } label: { Text(step == 1 ? "Add expenses →" : "Settle up →").frame(maxWidth: .infinity) }.buttonStyle(WebButton())
                } else { Button("New tab", action: home).frame(maxWidth: .infinity) }
            }
        }
    }
    private var identityPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Who are you?").font(Brand.ui(.largeTitle, weight: .bold))
                    Text("Pick your name or add yourself to the tab.").foregroundStyle(.secondary)
                    ForEach(current.people) { person in
                        PersonPill(name: person.name, selected: person.id.uuidString == identity) { setIdentity(person.id.uuidString); pickingIdentity = false }
                    }
                    HStack {
                        TextField("Your name", text: $newName).webInput()
                        Button("+ Add") {
                            perform {
                                try store.addPerson(newName, tabID: tab.id)
                                if let person = current.people.first(where: { $0.name == newName.trimmingCharacters(in: .whitespacesAndNewlines) }) { setIdentity(person.id.uuidString) }
                                newName = ""; pickingIdentity = false
                            }
                        }.buttonStyle(WebButton(primary: false))
                    }
                    Button("Skip for now") { setIdentity(""); pickingIdentity = false }.frame(maxWidth: .infinity, minHeight: 44)
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(20).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(Brand.background)
        }.font(Brand.ui())
    }
    private func setIdentity(_ value: String) { identity = value; UserDefaults.standard.set(value, forKey: "identity-\(tab.id)") }
    private func share() {
        sharing = true
        Task {
            defer { sharing = false }
            do { shared = try await store.prepareShare(tabID: tab.id) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); error = nil } catch { self.error = error.localizedDescription } }
}

struct PersonBreakdown: View {
    let tab: TabSnapshot
    let person: Person
    let isMe: Bool
    let payments: [SuggestedPayment]
    @State private var expanded = false
    private var paid: Int { tab.expenses.filter { $0.payer == person.id }.reduce(0) { $0 + $1.cents } }
    private var share: Int { tab.expenses.reduce(0) { $0 + ($1.shares[person.id] ?? 0) } }
    private var net: Int { Settlement.balances(tab)[person.id, default: 0] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(isMe ? "You" : person.name).font(Brand.ui(.subheadline, weight: .semibold))
                    Spacer()
                    Text(net == 0 ? "settled ✓" : net > 0 ? "is owed \(Money.text(net))" : "owes \(Money.text(-net))").font(Brand.ui(.subheadline)).foregroundStyle(net == 0 ? .green : Brand.accent)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain)
            HStack { stat("Paid", paid); stat("Share", share); stat("Net", net) }
            Text("\(isMe ? "You" : person.name) paid \(Money.text(paid)), \(isMe ? "your" : "their") share was \(Money.text(share)). \(net == 0 ? "All settled." : net > 0 ? "The group owes \(isMe ? "you" : "them") \(Money.text(net))." : "\(isMe ? "You owe" : "They owe") \(Money.text(-net)).")")
                .font(Brand.ui(.subheadline)).foregroundStyle(.secondary)
            if expanded {
                Divider()
                Text(isMe ? "WHAT YOU PAID" : "WHAT THEY PAID").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                ForEach(tab.expenses.filter { $0.payer == person.id }) { expense in row(expense.title, cents: expense.cents) }
                Text(isMe ? "YOUR PORTION" : "THEIR PORTION").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                ForEach(tab.expenses.filter { $0.shares[person.id] != nil }) { expense in
                    VStack(alignment: .leading, spacing: 3) {
                        row(expense.title, cents: expense.shares[person.id] ?? 0)
                        Text("\(tab.person(expense.payer)) paid").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                    }
                }
                ForEach(payments.filter { $0.from == person.id || $0.to == person.id }) { payment in
                    row(payment.from == person.id ? "Pay \(tab.person(payment.to))" : "\(tab.person(payment.from)) pays you", cents: payment.cents)
                        .strikethrough(Settlement.markedPayment(payment, in: tab) != nil)
                }
            }
        }.webCard().overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isMe ? Brand.accent : .clear))
            .onAppear { expanded = isMe }
    }
    private func stat(_ title: String, _ cents: Int) -> some View {
        VStack(spacing: 5) { MoneyLabel(cents: cents, style: .subheadline); Text(title).font(Brand.ui(.caption)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
    private func row(_ title: String, cents: Int) -> some View { HStack { Text(title); Spacer(); MoneyLabel(cents: cents, style: .subheadline) }.font(Brand.ui(.subheadline)) }
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
                Section("iCloud status") {
                    Text(store.cloudAccount)
                    LabeledContent("Last upload", value: store.lastExport?.formatted() ?? "Not observed this session")
                    LabeledContent("Last download", value: store.lastImport?.formatted() ?? "Not observed this session")
                    Button("Check iCloud account") { Task { await store.checkCloudAccount() } }
                    Text("An upload or download event is not confirmation that another device received a tab.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Recent sync events") {
                        ForEach(Array(store.syncDetails.enumerated()), id: \.offset) { _, detail in Text(detail).font(.caption).textSelection(.enabled) }
                    }
                    ShareLink("Share sync diagnostics", item: (["SettlingUp", store.cloudAccount, store.status] + store.syncDetails).joined(separator: "\n"))
                }
                Section("Privacy") {
                    Text("Names, expenses, and recorded payments stay on your device and in your Apple iCloud account. People you invite can access the shared tab. SettlingUp does not process payments or include advertising or analytics.")
                    Text("Backups contain your tab data. Store them somewhere private.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("SettlingUp · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))").foregroundStyle(.secondary) }
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
