import SwiftUI

struct ExpenseEditor: View {
    @EnvironmentObject private var store: TabStore
    @Environment(\.dismiss) private var dismiss
    let tab: TabSnapshot
    let original: Expense?
    @State private var title: String
    @State private var amount: String
    @State private var payer: UUID
    @State private var included: Set<UUID>
    @State private var mode: SplitMode
    @State private var personal: UUID
    @State private var custom: [UUID: String]
    @State private var tax: String
    @State private var tip: String
    @State private var error: String?

    init(tab: TabSnapshot, original: Expense? = nil) {
        self.tab = tab; self.original = original
        let first = tab.people.first?.id ?? UUID()
        _title = State(initialValue: original?.title ?? "")
        _amount = State(initialValue: original.map { Money.input($0.cents - $0.tax - $0.tip) } ?? "")
        _payer = State(initialValue: original?.payer ?? first)
        _included = State(initialValue: original.map { Set($0.shares.keys) } ?? Set(tab.people.map(\.id)))
        _mode = State(initialValue: original?.mode ?? .even)
        _personal = State(initialValue: original?.shares.keys.first ?? first)
        _custom = State(initialValue: (original?.bases.isEmpty == false ? original!.bases : original?.shares ?? [:]).mapValues(Money.input))
        _tax = State(initialValue: original.map { Money.input($0.tax) } ?? "")
        _tip = State(initialValue: original.map { Money.input($0.tip) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("What was it for?", text: $title).textInputAutocapitalization(.sentences)
                    Picker("Paid by", selection: $payer) { ForEach(tab.people) { Text($0.name).tag($0.id) } }
                    Picker("Split", selection: $mode) { ForEach(SplitMode.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section {
                    if mode == .custom {
                        ForEach(tab.people) { person in
                            HStack {
                                Text(person.name)
                                Spacer(minLength: 12)
                                TextField("0.00", text: Binding(get: { custom[person.id] ?? "" }, set: { custom[person.id] = $0 }))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 80)
                                    .accessibilityLabel("\(person.name)'s amount")
                            }
                        }
                    } else {
                        LabeledContent("Amount (USD)") { TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("Amount in US dollars") }
                    }
                    LabeledContent("Tax") { TextField("0.00", text: $tax).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("Tax amount") }
                    LabeledContent("Tip") { TextField("0.00", text: $tip).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("Tip amount") }
                } header: { Text(mode == .custom ? "Each person's amount (USD)" : "Amounts") } footer: {
                    Text(mode == .custom ? "Tax and tip are allocated proportionally, exactly to the cent." : "Tax and tip are added to the amount before splitting.")
                }
                if mode == .even {
                    Section("Split between") {
                        ForEach(tab.people) { person in
                            Toggle(person.name, isOn: Binding(get: { included.contains(person.id) }, set: { value in
                                if value { included.insert(person.id) } else { included.remove(person.id) }
                            }))
                        }
                    }
                } else if mode == .personal {
                    Section { Picker("For", selection: $personal) { ForEach(tab.people) { Text($0.name).tag($0.id) } } } header: { Text("Who owes this expense?") }
                }
                if let expense = try? draft() {
                    Section("Preview") {
                        HStack { Text("Total"); Spacer(); MoneyLabel(cents: expense.cents) }
                        ForEach(tab.people.filter { expense.shares[$0.id] != nil }) { person in
                            HStack { Text(person.name); Spacer(); MoneyLabel(cents: expense.shares[person.id] ?? 0) }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) } }
            }
            .navigationTitle(original == nil ? "Add expense" : "Edit expense").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try store.save(draft(), tabID: tab.id, original: original); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
        }
    }

    private func draft() throws -> Expense {
        let tax = try Money.parse(tax.isEmpty ? "0" : tax), tip = try Money.parse(tip.isEmpty ? "0" : tip)
        var shares: [UUID: Int], bases: [UUID: Int] = [:]
        let cents: Int
        if mode == .custom {
            for person in tab.people {
                let text = custom[person.id] ?? ""
                bases[person.id] = try Money.parse(text.isEmpty ? "0" : text)
            }
            shares = try Settlement.custom(bases: bases, tax: tax, tip: tip)
            cents = shares.values.reduce(0, +)
        } else {
            cents = try Money.parse(amount) + tax + tip
            let ids = mode == .personal ? [personal] : tab.people.filter { included.contains($0.id) }.map(\.id)
            shares = try Settlement.even(cents: cents, people: ids)
        }
        let expense = Expense(id: original?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), payer: payer, cents: cents, shares: shares, mode: mode, tax: tax, tip: tip, bases: bases, date: original?.date ?? Date())
        try expense.validate(people: Set(tab.people.map(\.id)))
        return expense
    }
}
