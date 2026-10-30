import Foundation
import CryptoKit

enum TabError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum Money {
    static let maximum = 100_000_000
    static let maximumPayment = maximum * 10_000
    static func parse(_ text: String) throws -> Int {
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^\d{1,7}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            throw TabError.invalid("Enter an amount with up to two decimal places.")
        }
        let cents = NSDecimalNumber(decimal: decimal * 100).intValue
        guard cents <= maximum else { throw TabError.invalid("Enter an amount of $1,000,000 or less.") }
        return cents
    }
    static func text(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD"))
    }
    static func input(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100)
            .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}

struct Person: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
}

enum SplitMode: String, Codable, CaseIterable, Identifiable {
    case even = "Even", custom = "Custom", personal = "Personal"
    var id: String { rawValue }
}

struct Expense: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var payer: UUID
    var cents: Int
    var shares: [UUID: Int]
    var mode: SplitMode
    var tax: Int = 0
    var tip: Int = 0
    var bases: [UUID: Int] = [:]
    var date: Date = Date()

    func validate(people: Set<UUID>) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, cents > 0, cents <= Money.maximum,
              people.contains(payer), !shares.isEmpty, Set(shares.keys).isSubset(of: people),
              Set(bases.keys).isSubset(of: people), bases.values.allSatisfy({ $0 >= 0 && $0 <= Money.maximum }),
              shares.values.allSatisfy({ $0 >= 0 && $0 <= Money.maximum }),
              shares.values.reduce(0, +) == cents,
              tax >= 0, tip >= 0, tax <= Money.maximum, tip <= Money.maximum, tax + tip <= cents else {
            throw TabError.invalid("Check the description, payer, and split amounts. Shares must total the expense.")
        }
    }
}

struct Transfer: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var from: UUID
    var to: UUID
    var cents: Int
    var date: Date = Date()
}

struct SuggestedPayment: Identifiable, Equatable {
    var from: UUID
    var to: UUID
    var cents: Int
    var id: String { from.uuidString + to.uuidString }
}

struct TabSnapshot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var created: Date = Date()
    var people: [Person] = []
    var expenses: [Expense] = []
    var transfers: [Transfer] = []
    var total: Int { expenses.reduce(0) { $0 + $1.cents } }
    func person(_ id: UUID) -> String { people.first { $0.id == id }?.name ?? "Unknown person" }

    func privateCopy() -> TabSnapshot {
        let identities = Dictionary(uniqueKeysWithValues: people.map { ($0.id, UUID()) })
        var copy = self
        copy.id = UUID()
        copy.people = people.map { Person(id: identities[$0.id]!, name: $0.name) }
        copy.expenses = expenses.map { expense in
            var result = expense
            result.id = UUID(); result.payer = identities[expense.payer]!
            result.shares = Dictionary(uniqueKeysWithValues: expense.shares.map { (identities[$0.key]!, $0.value) })
            result.bases = Dictionary(uniqueKeysWithValues: expense.bases.compactMap { key, value in identities[key].map { ($0, value) } })
            return result
        }
        copy.transfers = transfers.map { Transfer(from: identities[$0.from]!, to: identities[$0.to]!, cents: $0.cents, date: $0.date) }
        return copy
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              people.count <= 100, expenses.count <= 10_000, transfers.count <= 10_000,
              Set(people.map(\.id)).count == people.count,
              Set(expenses.map(\.id)).count == expenses.count,
              Set(transfers.map(\.id)).count == transfers.count,
              people.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }) else {
            throw TabError.invalid("This tab contains invalid or duplicate records.")
        }
        let ids = Set(people.map(\.id))
        for expense in expenses { try expense.validate(people: ids) }
        for transfer in transfers {
            guard ids.contains(transfer.from), ids.contains(transfer.to), transfer.from != transfer.to,
                  transfer.cents > 0, transfer.cents <= Money.maximumPayment else {
                throw TabError.invalid("This tab contains an invalid payment.")
            }
        }
    }
}

enum Settlement {
    static func paymentID(_ payment: SuggestedPayment, tab: TabSnapshot) -> UUID {
        // Two people recording the same suggestion from the same ledger create one logical payment.
        var parts = [tab.id.uuidString, payment.from.uuidString, payment.to.uuidString, String(payment.cents)]
        for expense in tab.expenses.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            parts += [expense.id.uuidString, expense.payer.uuidString, String(expense.cents)]
            for id in expense.shares.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                parts += [id.uuidString, String(expense.shares[id]!)]
            }
        }
        parts += tab.transfers.map { $0.id.uuidString }.sorted()
        let hex = SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let characters = Array(hex)
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(characters[$0]) }
        return UUID(uuidString: groups.joined(separator: "-"))!
    }

    static func even(cents: Int, people: [UUID]) throws -> [UUID: Int] {
        guard cents >= 0, cents <= Money.maximum, !people.isEmpty,
              Set(people).count == people.count else { throw TabError.invalid("Choose who is splitting this expense.") }
        return Dictionary(uniqueKeysWithValues: people.enumerated().map {
            ($0.element, cents / people.count + ($0.offset < cents % people.count ? 1 : 0))
        })
    }

    static func custom(bases: [UUID: Int], tax: Int, tip: Int) throws -> [UUID: Int] {
        guard !bases.isEmpty, bases.values.allSatisfy({ $0 >= 0 && $0 <= Money.maximum }),
              tax >= 0, tip >= 0, tax <= Money.maximum, tip <= Money.maximum else {
            throw TabError.invalid("Enter valid custom amounts, tax and tip.")
        }
        let total = bases.values.reduce(0, +)
        guard total > 0, total + tax + tip <= Money.maximum else {
            throw TabError.invalid("Custom amounts must total more than zero and at most $1,000,000 including tax and tip.")
        }
        let extras = tax + tip
        let ranked = bases.keys.sorted {
            let left = Int64(bases[$0]!) * Int64(extras) % Int64(total)
            let right = Int64(bases[$1]!) * Int64(extras) % Int64(total)
            return left == right ? $0.uuidString < $1.uuidString : left > right
        }
        var result = bases.mapValues { $0 + Int(Int64($0) * Int64(extras) / Int64(total)) }
        let remainder = total + extras - result.values.reduce(0, +)
        for id in ranked.prefix(remainder) { result[id, default: 0] += 1 }
        return result.filter { $0.value > 0 }
    }

    static func balances(_ tab: TabSnapshot) -> [UUID: Int] {
        var result = Dictionary(uniqueKeysWithValues: tab.people.map { ($0.id, 0) })
        for expense in tab.expenses {
            result[expense.payer, default: 0] += expense.cents
            for (person, cents) in expense.shares { result[person, default: 0] -= cents }
        }
        for transfer in tab.transfers {
            result[transfer.from, default: 0] += transfer.cents
            result[transfer.to, default: 0] -= transfer.cents
        }
        return result
    }

    static func smart(_ tab: TabSnapshot) -> [SuggestedPayment] {
        var balances = balances(tab)
        let ids = tab.people.map(\.id).sorted { $0.uuidString < $1.uuidString }
        var payments: [SuggestedPayment] = []
        while let debtor = ids.filter({ balances[$0, default: 0] < 0 }).min(by: { balances[$0]! < balances[$1]! }),
              let creditor = ids.filter({ balances[$0, default: 0] > 0 }).max(by: { balances[$0]! < balances[$1]! }) {
            let amount = min(-balances[debtor]!, balances[creditor]!)
            payments.append(.init(from: debtor, to: creditor, cents: amount))
            balances[debtor]! += amount
            balances[creditor]! -= amount
        }
        return payments
    }

    static func direct(_ tab: TabSnapshot) -> [SuggestedPayment] {
        var debts: [UUID: [UUID: Int]] = [:]
        for expense in tab.expenses {
            for (person, cents) in expense.shares where person != expense.payer {
                debts[person, default: [:]][expense.payer, default: 0] += cents
            }
        }
        for transfer in tab.transfers {
            debts[transfer.from, default: [:]][transfer.to, default: 0] -= transfer.cents
        }
        let ids = tab.people.map(\.id)
        var result: [SuggestedPayment] = []
        for i in ids.indices {
            for j in ids.indices where j > i {
                let a = ids[i], b = ids[j]
                let net = debts[a]?[b, default: 0] ?? 0
                let reverse = debts[b]?[a, default: 0] ?? 0
                if net > reverse { result.append(.init(from: a, to: b, cents: net - reverse)) }
                if reverse > net { result.append(.init(from: b, to: a, cents: reverse - net)) }
            }
        }
        return result
    }
}
