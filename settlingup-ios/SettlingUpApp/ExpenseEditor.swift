import SwiftUI

struct ExpenseEditor: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.dismiss) private var dismiss
    let tab: TabSnapshot
    let original: Expense?
    var inline = false
    var onSaved: (() -> Void)?
    @State private var title: String
    @State private var amount: String
    @State private var payer: UUID?
    @State private var included: Set<UUID>
    @State private var mode: SplitMode
    @State private var personal: UUID?
    @State private var custom: [UUID: String]
    @State private var tax: String
    @State private var tip: String
    @State private var error: String?
    @State private var topDriven = true

    init(tab: TabSnapshot, original: Expense? = nil, inline: Bool = false, onSaved: (() -> Void)? = nil) {
        self.tab = tab; self.original = original; self.inline = inline; self.onSaved = onSaved
        let lastPayer = UserDefaults.standard.string(forKey: "payer-\(tab.id)").flatMap(UUID.init(uuidString:))
        _topDriven = State(initialValue: original == nil)
        _title = State(initialValue: original?.title ?? "")
        _amount = State(initialValue: original.map { Money.input($0.cents) } ?? "")
        _payer = State(initialValue: original?.payer ?? (tab.people.contains { $0.id == lastPayer } ? lastPayer : nil))
        _included = State(initialValue: original.map { Set($0.shares.keys) } ?? Set(tab.people.map(\.id)))
        _mode = State(initialValue: original?.mode ?? SplitMode(rawValue: UserDefaults.standard.string(forKey: "split-\(tab.id)") ?? "") ?? .even)
        _personal = State(initialValue: original?.mode == .personal ? original?.shares.keys.first : nil)
        _custom = State(initialValue: (original?.bases.isEmpty == false ? original!.bases : original?.shares ?? [:]).mapValues(Money.input))
        _tax = State(initialValue: original.map { Money.input($0.tax) } ?? "")
        _tip = State(initialValue: original.map { Money.input($0.tip) } ?? "")
    }

    var body: some View {
        Group {
            if inline { form }
            else {
                NavigationStack {
                    ScrollView { form.padding().frame(maxWidth: 480).frame(maxWidth: .infinity) }.background(Brand.background)
                        .navigationTitle("Edit expense").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }
        }
        .font(Brand.ui())
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        } }
    }

    private func name(_ person: Person) -> String {
        UserDefaults.standard.string(forKey: "identity-\(tab.id)") == person.id.uuidString ? "You" : person.name
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "NEW EXPENSE" : "EDITING EXPENSE").font(Brand.ui(.caption, weight: .semibold)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { descriptionField; amountField.frame(width: 112) }
                VStack(alignment: .leading, spacing: 10) { descriptionField; amountField }
            }
            Text("WHO PAID?").font(Brand.ui(.caption)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 8) {
                ForEach(tab.people) { person in PersonPill(name: name(person), selected: payer == person.id) { payer = person.id } }
            }
            Divider()
            Text("HOW TO SPLIT").font(Brand.ui(.caption)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(SplitMode.allCases) { option in
                    Button(option.rawValue) { mode = option }
                        .buttonStyle(WebSegment(selected: mode == option))
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("How to split")
                .onChange(of: mode) { _, new in
                    included = Set(tab.people.map(\.id))
                    if new == .custom { topDriven = true; fillEvenly() }
                }
            if mode == .even {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 8) {
                    ForEach(tab.people) { person in
                        PersonPill(name: name(person), selected: included.contains(person.id)) { toggle(person.id) }
                    }
                }
                if let cents = try? Money.parse(amount), !included.isEmpty {
                    Text("\(Money.text(cents)) ÷ \(included.count) people · \(Money.text(cents / included.count)) each\(cents % included.count == 0 ? "" : " (extra cents distributed fairly)")")
                        .font(Brand.ui(.caption)).foregroundStyle(.secondary)
                }
            } else if mode == .personal {
                Text("WHO IS IT FOR?").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 8) {
                    ForEach(tab.people) { person in PersonPill(name: name(person), selected: personal == person.id) { personal = person.id } }
                }
            } else {
                HStack {
                    Text("PER PERSON").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                    Spacer()
                    Button("⚡ Split evenly") { fillEvenly(showError: true); topDriven = false }.font(Brand.ui(.caption)).frame(minHeight: 44)
                }
                Text("Tap to include/exclude").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                ForEach(tab.people) { person in
                    HStack {
                        Button { toggle(person.id); custom[person.id] = ""; topDriven = false; updateTotal() } label: {
                            Image(systemName: included.contains(person.id) ? "checkmark.circle.fill" : "plus.circle")
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("\(included.contains(person.id) ? "Exclude" : "Include") \(person.name)")
                        Text(name(person)).font(Brand.ui(.subheadline))
                        Spacer(minLength: 4)
                        TextField("0.00", text: Binding(get: { custom[person.id] ?? "" }, set: {
                            custom[person.id] = $0; topDriven = false; updateTotal()
                        })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(Brand.number(.subheadline))
                            .webInput().frame(width: 100).disabled(!included.contains(person.id))
                            .accessibilityLabel("\(person.name)'s share before tax and tip")
                    }.opacity(included.contains(person.id) ? 1 : 0.5)
                }
                HStack(spacing: 12) {
                    extraField("Tax (optional)", text: $tax)
                    extraField("Tip (optional)", text: $tip)
                }
            }
            if let expense = try? draft(requireTitle: false) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Total").font(Brand.ui(.subheadline, weight: .semibold)); Spacer(); MoneyLabel(cents: expense.cents).foregroundStyle(Brand.accent) }
                    ForEach(tab.people.filter { expense.shares[$0.id] != nil }) { person in
                        HStack { Text(name(person)); Spacer(); MoneyLabel(cents: expense.shares[person.id] ?? 0, style: .subheadline) }
                    }
                }.font(Brand.ui(.subheadline)).padding(.vertical, 6)
            }
            if let error { Text(error).font(Brand.ui(.subheadline)).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
            Button { save() } label: { Text(original == nil ? "+ Add expense" : "Save changes").frame(maxWidth: .infinity) }.buttonStyle(WebButton())
        }.webCard().overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.accent))
    }
    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESCRIPTION").font(Brand.ui(.caption)).foregroundStyle(.secondary)
            TextField("Gas, Dinner, Hotel…", text: $title).textInputAutocapitalization(.sentences).webInput()
        }
    }
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AMOUNT ($)").font(Brand.ui(.caption)).foregroundStyle(.secondary)
            TextField("0.00", text: Binding(get: { amount }, set: { amount = $0; topDriven = true; if mode == .custom { fillEvenly() } }))
                .keyboardType(.decimalPad).font(Brand.number()).webInput().accessibilityLabel("Total amount")
        }
    }
    private func extraField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Brand.ui(.caption)).foregroundStyle(.secondary)
            TextField("0.00", text: Binding(get: { text.wrappedValue }, set: {
                text.wrappedValue = $0
                if topDriven { fillEvenly() } else { updateTotal() }
            })).keyboardType(.decimalPad).font(Brand.number()).webInput().accessibilityLabel(label)
        }
    }
    private func toggle(_ id: UUID) { if included.contains(id) { included.remove(id) } else { included.insert(id) } }
    private func parsed(_ text: String) throws -> Int { try Money.parse(text.isEmpty ? "0" : text) }
    private func fillEvenly(showError: Bool = false) {
        do {
            let total = try Money.parse(amount)
            let base = total - (try parsed(tax)) - (try parsed(tip))
            guard base > 0 else { throw TabError.invalid("The total must be greater than tax and tip.") }
            custom = try Settlement.even(cents: base, people: tab.people.filter { included.contains($0.id) }.map(\.id)).mapValues(Money.input)
            topDriven = false
            error = nil
        } catch { if showError { self.error = error.localizedDescription } }
    }
    private func updateTotal() {
        do {
            let values = try tab.people.filter { included.contains($0.id) }.map { try parsed(custom[$0.id] ?? "") }
            amount = Money.input(values.reduce(0, +) + (try parsed(tax)) + (try parsed(tip)))
        } catch { /* Keep the user's unfinished input until it becomes a valid amount. */ }
    }
    private func draft(requireTitle: Bool = true) throws -> Expense {
        guard let payer = payer ?? (requireTitle ? nil : tab.people.first?.id) else { throw TabError.invalid("Select who paid.") }
        var shares: [UUID: Int], bases: [UUID: Int] = [:]
        let cents = try Money.parse(amount)
        let tax = mode == .custom ? try parsed(tax) : 0
        let tip = mode == .custom ? try parsed(tip) : 0
        if mode == .custom {
            for person in tab.people where included.contains(person.id) {
                let base = try parsed(custom[person.id] ?? "")
                if base > 0 { bases[person.id] = base }
            }
            shares = try Settlement.custom(bases: bases, tax: tax, tip: tip, people: tab.people.map(\.id))
            guard shares.values.reduce(0, +) == cents else { throw TabError.invalid("Per-person amounts, tax and tip must match the total. Tap Split evenly or adjust the amounts.") }
        } else {
            if mode == .personal && personal == nil { throw TabError.invalid("Select who this is for.") }
            let ids = mode == .personal ? [personal!] : tab.people.filter { included.contains($0.id) }.map(\.id)
            shares = try Settlement.even(cents: cents, people: ids, rotation: original?.splitRotation ?? (original == nil ? tab.expenses.count : 0))
        }
        let expense = Expense(id: original?.id ?? UUID(), title: requireTitle ? title.trimmingCharacters(in: .whitespacesAndNewlines) : "Preview", payer: payer, cents: cents, shares: shares, mode: mode, tax: tax, tip: tip, bases: bases, splitRotation: original?.splitRotation ?? (original == nil ? tab.expenses.count : 0), date: original?.date ?? Date())
        try expense.validate(people: Set(tab.people.map(\.id)))
        return expense
    }
    private func save() {
        do {
            let expense = try draft()
            try store.save(expense, tabID: tab.id, original: original)
            UserDefaults.standard.set(expense.payer.uuidString, forKey: "payer-\(tab.id)")
            UserDefaults.standard.set(mode.rawValue, forKey: "split-\(tab.id)")
            error = nil
            if inline {
                title = ""; amount = ""; custom = [:]; tax = ""; tip = ""
                included = Set(tab.people.map(\.id)); personal = nil; topDriven = true; onSaved?()
            } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
