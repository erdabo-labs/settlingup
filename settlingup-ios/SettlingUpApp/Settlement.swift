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
        guard normalized.range(of: #"^(?:\d{1,7}(?:\.\d{0,2})?|\.\d{1,2})$"#, options: .regularExpression) != nil,
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

enum WebsiteTab {
    static func url(for input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^[A-Za-z0-9]{4,12}$"#, options: .regularExpression) != nil {
            return URL(string: "https://www.settlingup.app/t/" + text)!
        }
        guard let url = URL(string: text), url.scheme == "https",
              ["settlingup.app", "www.settlingup.app"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              (url.path.range(of: #"^/t/[A-Za-z0-9]{4,12}/?$"#, options: .regularExpression) != nil ||
               ((url.path.isEmpty || url.path == "/") && url.fragment?.range(of: #"^v2\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil)) else {
            throw TabError.invalid("Enter a website tab code or a settlingup.app tab link.")
        }
        return url
    }
}

struct Person: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var order: Int? = nil
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
    var splitRotation: Int? = nil
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
        copy.people = people.map { Person(id: identities[$0.id]!, name: $0.name, order: $0.order) }
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
    // The website keeps payment cards visible after marking them paid.
    static func displayedPayments(_ tab: TabSnapshot, direct: Bool = false) -> [SuggestedPayment] {
        var expensesOnly = tab
        expensesOnly.transfers = []
        return direct ? self.direct(expensesOnly) : smart(expensesOnly)
    }

    static func markedPayment(_ payment: SuggestedPayment, in tab: TabSnapshot) -> Transfer? {
        tab.transfers.first { $0.from == payment.from && $0.to == payment.to && abs($0.cents - payment.cents) <= 1 }
    }

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

    static func even(cents: Int, people: [UUID], rotation: Int = 0) throws -> [UUID: Int] {
        guard cents >= 0, cents <= Money.maximum, !people.isEmpty,
              Set(people).count == people.count else { throw TabError.invalid("Choose who is splitting this expense.") }
        return Dictionary(uniqueKeysWithValues: people.enumerated().map {
            ($0.element, cents / people.count + ((($0.offset + abs(rotation % people.count)) % people.count) < cents % people.count ? 1 : 0))
        })
    }

    static func custom(bases: [UUID: Int], tax: Int, tip: Int, people: [UUID] = []) throws -> [UUID: Int] {
        guard !bases.isEmpty, bases.values.allSatisfy({ $0 >= 0 && $0 <= Money.maximum }),
              tax >= 0, tip >= 0, tax <= Money.maximum, tip <= Money.maximum else {
            throw TabError.invalid("Enter valid custom amounts, tax and tip.")
        }
        let total = bases.values.reduce(0, +)
        guard total > 0, total + tax + tip <= Money.maximum else {
            throw TabError.invalid("Custom amounts must total more than zero and at most $1,000,000 including tax and tip.")
        }
        // Match index.html: round each share, then correct the largest fraction.
        // Dollar operations preserve the website's observable floating-point tie order.
        let ordered = people.filter { bases[$0] != nil } + bases.keys.filter { !people.contains($0) }.sorted { $0.uuidString < $1.uuidString }
        let subtotal = ordered.reduce(0.0) { $0 + Double(bases[$1]!) / 100 }
        let extras = Double(tax) / 100 + Double(tip) / 100
        var fractions: [UUID: Double] = [:]
        var result: [UUID: Int] = [:]
        for id in ordered {
            let base = Double(bases[id]!) / 100
            let share = base + (base / subtotal) * extras
            fractions[id] = share - floor(share * 100) / 100
            result[id] = Int(floor(share * 100 + 0.5))
        }
        let correction = total + tax + tip - result.values.reduce(0, +)
        let ranked = ordered.enumerated().filter { bases[$0.element]! > 0 }.sorted {
            if fractions[$0.element] != fractions[$1.element] { return fractions[$0.element]! > fractions[$1.element]! }
            return $0.offset < $1.offset
        }.map(\.element)
        if let winner = ranked.first {
            if result[winner]! + correction >= 0 {
                result[winner]! += correction
            } else {
                // The web drops a negative corrected share for many tiny bases,
                // losing money. In that case use exact largest-remainder allocation.
                let extraCents = tax + tip
                let exactOrder = ordered.enumerated().sorted {
                    let left = Int64(bases[$0.element]!) * Int64(extraCents) % Int64(total)
                    let right = Int64(bases[$1.element]!) * Int64(extraCents) % Int64(total)
                    return left == right ? $0.offset < $1.offset : left > right
                }.map(\.element)
                result = bases.mapValues { $0 + Int(Int64($0) * Int64(extraCents) / Int64(total)) }
                let remainder = total + extraCents - result.values.reduce(0, +)
                for id in exactOrder.prefix(remainder) { result[id, default: 0] += 1 }
            }
        }
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
        let ids = tab.people.map(\.id)
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


struct DemoScenario: Decodable, Identifiable {
    struct DemoPerson: Decodable { let id: Int; let name: String }
    struct DemoExpense: Decodable {
        let id: Int; let desc: String; let amount: Double; let paidBy: Int
        let splitType: String; let splitWith: [Int]; let splitAmounts: [String: Double]?
    }
    let title: String
    let icon: String
    let people: [DemoPerson]
    let expenses: [DemoExpense]
    var id: String { title }

    func snapshot() throws -> TabSnapshot {
        let people = people.enumerated().map { Person(name: $0.element.name, order: $0.offset) }
        let ids = Dictionary(uniqueKeysWithValues: zip(self.people.map(\.id), people.map(\.id)))
        var tab = TabSnapshot(name: "DEMO: " + title, people: people)
        for (index, source) in expenses.enumerated() {
            let cents = Int((source.amount * 100).rounded())
            let included = try source.splitWith.map { value -> UUID in
                guard let id = ids[value] else { throw TabError.invalid("Invalid demo participant") }; return id
            }
            let shares: [UUID: Int]
            if let amounts = source.splitAmounts {
                shares = Dictionary(uniqueKeysWithValues: try amounts.map { key, value in
                    guard let numeric = Int(key), let id = ids[numeric] else { throw TabError.invalid("Invalid demo split") }
                    return (id, Int((value * 100).rounded()))
                })
            } else { shares = try Settlement.even(cents: cents, people: included, rotation: source.id) }
            guard let payer = ids[source.paidBy] else { throw TabError.invalid("Invalid demo payer") }
            let mode: SplitMode = source.splitType == "custom" ? .custom : source.splitType == "personal" ? .personal : .even
            tab.expenses.append(Expense(title: source.desc, payer: payer, cents: cents, shares: shares, mode: mode,
                                        bases: mode == .custom ? shares : [:], splitRotation: source.id,
                                        date: Date().addingTimeInterval(Double(index))))
        }
        try tab.validate()
        return tab
    }

    // Copied from settlingup-demos.js so the native examples exercise the original scenarios.
    static let bundledJSON = #"""
[{"title":"Bach Party Vegas","icon":"🥂","color":"rgba(155,69,186,0.18)","people":[{"id":0,"name":"Jordan"},{"id":1,"name":"Taylor"},{"id":2,"name":"Morgan"},{"id":3,"name":"Riley"},{"id":4,"name":"Casey"},{"id":5,"name":"Avery"},{"id":6,"name":"Quinn"},{"id":7,"name":"Blake"},{"id":8,"name":"Sage"},{"id":9,"name":"Drew"},{"id":10,"name":"Reese"},{"id":11,"name":"Alex"}],"expenses":[{"id":0,"desc":"Airbnb — 2 nights","amount":1440,"paidBy":0,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":1,"desc":"Matching sashes & accessories","amount":156,"paidBy":1,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10],"splitAmounts":null},{"id":2,"desc":"Drag brunch tickets","amount":480,"paidBy":2,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":3,"desc":"Pool party cabana","amount":350,"paidBy":0,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":4,"desc":"Dinner — steakhouse","amount":892.5,"paidBy":3,"splitType":"custom","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":{"0":72,"1":68.5,"2":95,"3":55,"4":88,"5":72,"6":65,"7":90,"8":55,"9":78,"10":68,"11":86}},{"id":5,"desc":"Nightclub entry + bottle","amount":1200,"paidBy":4,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":6,"desc":"Ubers — night out (x4 cars)","amount":148,"paidBy":5,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":7,"desc":"Brunch Day 2","amount":320,"paidBy":6,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":8,"desc":"Honouree's flight contribution","amount":300,"paidBy":7,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10],"splitAmounts":null},{"id":9,"desc":"Spa treatments","amount":660,"paidBy":8,"splitType":"even","splitWith":[0,2,4,6,8,10],"splitAmounts":null},{"id":10,"desc":"Cocktail making class","amount":420,"paidBy":9,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null},{"id":11,"desc":"Late-night snacks & drinks","amount":185,"paidBy":10,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7,8,9,10,11],"splitAmounts":null}]},{"title":"Family Beach Trip","icon":"🏖️","color":"rgba(0,212,255,0.12)","people":[{"id":0,"name":"Dad (Mike)"},{"id":1,"name":"Mom (Sarah)"},{"id":2,"name":"Uncle Dave"},{"id":3,"name":"Aunt Linda"},{"id":4,"name":"Grandpa Joe"},{"id":5,"name":"Grandma Sue"},{"id":6,"name":"Cousin Emma"},{"id":7,"name":"Cousin Ryan"}],"expenses":[{"id":0,"desc":"Beach house rental — 7 nights","amount":3500,"paidBy":0,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":null},{"id":1,"desc":"Groceries — week 1","amount":420,"paidBy":1,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":null},{"id":2,"desc":"Boat rental — day trip","amount":680,"paidBy":2,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":null},{"id":3,"desc":"Seafood dinner — night 2","amount":485,"paidBy":3,"splitType":"custom","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":{"0":72,"1":68,"2":65,"3":58,"4":52,"5":52,"6":60,"7":58}},{"id":4,"desc":"Gas — Mike's car (drove down)","amount":95,"paidBy":0,"splitType":"even","splitWith":[0,1,4,5],"splitAmounts":null},{"id":5,"desc":"Gas — Dave's car","amount":88,"paidBy":2,"splitType":"even","splitWith":[2,3,6,7],"splitAmounts":null},{"id":6,"desc":"Kayak & paddleboard rentals","amount":240,"paidBy":6,"splitType":"even","splitWith":[0,1,2,3,6,7],"splitAmounts":null},{"id":7,"desc":"Mini golf","amount":120,"paidBy":7,"splitType":"even","splitWith":[0,1,2,3,6,7],"splitAmounts":null},{"id":8,"desc":"Ice cream — daily runs","amount":85,"paidBy":4,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":null},{"id":9,"desc":"Aquarium tickets","amount":210,"paidBy":5,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":null},{"id":10,"desc":"Farewell dinner — nice restaurant","amount":620,"paidBy":0,"splitType":"custom","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":{"0":90,"1":85,"2":82,"3":78,"4":70,"5":70,"6":75,"7":70}},{"id":11,"desc":"Sunscreen & beach supplies","amount":68,"paidBy":1,"splitType":"even","splitWith":[0,1,2,3,4,5,6,7],"splitAmounts":null}]},{"title":"Date Night Out","icon":"🍷","color":"rgba(224,90,90,0.15)","people":[{"id":0,"name":"Sam"},{"id":1,"name":"Jamie"},{"id":2,"name":"Chris"},{"id":3,"name":"Pat"},{"id":4,"name":"Nico"},{"id":5,"name":"Mel"}],"expenses":[{"id":0,"desc":"Uber to dinner","amount":28.5,"paidBy":0,"splitType":"even","splitWith":[0,1,2,3,4,5],"splitAmounts":null},{"id":1,"desc":"Dinner — Osteria","amount":396.8,"paidBy":1,"splitType":"custom","splitWith":[0,1,2,3,4,5],"splitAmounts":{"0":58.88,"1":74.24,"2":66.56,"3":58.88,"4":69.12,"5":69.12}},{"id":2,"desc":"Wine — bottle at dinner","amount":95,"paidBy":2,"splitType":"even","splitWith":[0,1,2,3,4,5],"splitAmounts":null},{"id":3,"desc":"Bowling — shoes & games","amount":132,"paidBy":3,"splitType":"even","splitWith":[0,1,2,3,4,5],"splitAmounts":null},{"id":4,"desc":"Drinks at the bar","amount":148,"paidBy":4,"splitType":"even","splitWith":[0,1,2,3,4,5],"splitAmounts":null},{"id":5,"desc":"Uber home","amount":34,"paidBy":5,"splitType":"even","splitWith":[0,1,2,3,4,5],"splitAmounts":null},{"id":6,"desc":"Late-night pizza slice","amount":42,"paidBy":0,"splitType":"even","splitWith":[0,1,2,3,4,5],"splitAmounts":null}]}]
"""#
    static var all: [DemoScenario] { (try? JSONDecoder().decode([DemoScenario].self, from: Data(bundledJSON.utf8))) ?? [] }
}
