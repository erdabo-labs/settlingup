import XCTest
import CoreData
@testable import SettlingUp

final class SettlementTests: XCTestCase {
    func testTenDollarsAmongThree() throws {
        let ids = (0..<3).map { _ in UUID() }
        let shares = try Settlement.even(cents: 1000, people: ids)
        XCTAssertEqual(ids.map { shares[$0]! }, [334, 333, 333])
    }

    func testHundredDollarsAmongSeven() throws {
        let shares = try Settlement.even(cents: 10_000, people: (0..<7).map { _ in UUID() })
        XCTAssertEqual(shares.values.reduce(0, +), 10_000)
        XCTAssertEqual(shares.values.max()! - shares.values.min()!, 1)
    }

    func testSplitsConserveEveryCent() throws {
        let people = (0..<20).map { _ in UUID() }
        for count in 1...20 {
            for cents in stride(from: 0, through: 10000, by: 37) {
                let split = try Settlement.even(cents: cents, people: Array(people.prefix(count)))
                XCTAssertEqual(split.values.reduce(0, +), cents)
                XCTAssertLessThanOrEqual(split.values.max()! - split.values.min()!, 1)
            }
        }
    }

    func testCustomTaxTipUsesLargestRemainder() throws {
        let ids = (0..<7).map { _ in UUID() }
        let bases = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, ($0.offset + 1) * 101) })
        for extras in 0...100 {
            let shares = try Settlement.custom(bases: bases, tax: extras, tip: 231)
            XCTAssertEqual(shares.values.reduce(0, +), bases.values.reduce(0, +) + extras + 231)
            for id in ids { XCTAssertGreaterThanOrEqual(shares[id]!, bases[id]!) }
        }
    }

    func testInvalidInputsAreRejected() throws {
        let id = UUID()
        XCTAssertThrowsError(try Settlement.even(cents: 100, people: []))
        XCTAssertThrowsError(try Settlement.even(cents: -1, people: [id]))
        XCTAssertThrowsError(try Settlement.even(cents: 100, people: [id, id]))
        XCTAssertThrowsError(try Settlement.custom(bases: [id: 0], tax: 1, tip: 0))
        XCTAssertThrowsError(try Settlement.custom(bases: [id: 100], tax: -1, tip: 0))
        XCTAssertThrowsError(try Money.parse("NaN"))
        XCTAssertThrowsError(try Money.parse("1.001"))
        XCTAssertThrowsError(try Money.parse("-2"))
        XCTAssertThrowsError(try Money.parse("1000001"))
    }

    func testMoneyInputRoundTrip() throws {
        for cents in [0, 1, 101, 99999, Money.maximum] { XCTAssertEqual(try Money.parse(Money.input(cents)), cents) }
    }

    func testSmartPaymentsSettleAllBalances() throws {
        let people = (0..<7).map { Person(name: "Person \($0)") }
        var tab = TabSnapshot(name: "Trip", people: people)
        for i in 0..<30 {
            let amount = (i + 1) * 127
            tab.expenses.append(Expense(title: "Expense", payer: people[i % people.count].id, cents: amount,
                                        shares: try Settlement.even(cents: amount, people: people.map(\.id)), mode: .even))
        }
        XCTAssertEqual(Settlement.balances(tab).values.reduce(0, +), 0)
        let suggestions = Settlement.smart(tab)
        XCTAssertLessThanOrEqual(suggestions.count, people.count - 1)
        for payment in suggestions { tab.transfers.append(Transfer(from: payment.from, to: payment.to, cents: payment.cents)) }
        XCTAssertTrue(Settlement.balances(tab).values.allSatisfy { $0 == 0 })
        XCTAssertTrue(Settlement.smart(tab).isEmpty)
    }

    func testDirectPaymentsNetReciprocalExpenses() throws {
        let a = Person(name: "A"), b = Person(name: "B")
        let tab = TabSnapshot(name: "Dinner", people: [a, b], expenses: [
            Expense(title: "One", payer: a.id, cents: 1000, shares: [b.id: 1000], mode: .personal),
            Expense(title: "Two", payer: b.id, cents: 300, shares: [a.id: 300], mode: .personal)
        ])
        XCTAssertEqual(Settlement.direct(tab), [.init(from: b.id, to: a.id, cents: 700)])
    }

    func testEditedExpenseDoesNotEraseActualPayment() throws {
        let a = Person(name: "A"), b = Person(name: "B")
        var tab = TabSnapshot(name: "Dinner", people: [a, b], expenses: [Expense(title: "Dinner", payer: a.id, cents: 1000, shares: [a.id: 500, b.id: 500], mode: .even)])
        tab.transfers = [Transfer(from: b.id, to: a.id, cents: 500)]
        XCTAssertTrue(Settlement.smart(tab).isEmpty)
        tab.expenses[0].cents = 800; tab.expenses[0].shares = [a.id: 400, b.id: 400]
        XCTAssertEqual(Settlement.smart(tab), [.init(from: a.id, to: b.id, cents: 100)])
        try tab.validate()
    }

    func testPaymentIdentityIsStableAcrossOrderingAndChangesAfterPayment() throws {
        let a = Person(name: "A"), b = Person(name: "B")
        var tab = TabSnapshot(name: "Dinner", people: [a, b], expenses: [Expense(title: "Meal", payer: a.id, cents: 1000, shares: [a.id: 500, b.id: 500], mode: .even)])
        let payment = Settlement.smart(tab)[0]
        let id = Settlement.paymentID(payment, tab: tab)
        tab.people.reverse()
        XCTAssertEqual(Settlement.paymentID(payment, tab: tab), id)
        tab.transfers.append(Transfer(id: id, from: payment.from, to: payment.to, cents: payment.cents))
        XCTAssertNotEqual(Settlement.paymentID(payment, tab: tab), id)
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    private func fixture(_ store: TabStore) throws -> UUID {
        let id = try store.create(name: "Weekend", names: ["Erik", "Sam", "Alex"])
        let people = store.tabs.first!.people
        let expense = Expense(title: "Dinner", payer: people[0].id, cents: 1000,
                              shares: try Settlement.even(cents: 1000, people: people.map(\.id)), mode: .even)
        try store.save(expense, tabID: id)
        return id
    }

    func testDiskStoreReopensWithoutLosingRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = TabStore(directory: directory, cloud: false)
        XCTAssertTrue(first.ready, first.error ?? "")
        let id = try fixture(first)
        let expected = first.tabs
        for persistent in first.container.persistentStoreCoordinator.persistentStores {
            try first.container.persistentStoreCoordinator.remove(persistent)
        }
        let reopened = TabStore(directory: directory, cloud: false)
        XCTAssertEqual(reopened.tabs, expected)
        XCTAssertEqual(reopened.tabs.first?.id, id)
    }

    func testBackupRoundTripAndOverwriteProtection() throws {
        let source = TabStore(cloud: false, inMemory: true)
        let id = try fixture(source)
        try source.record(Settlement.smart(source.tabs[0])[0], tabID: id)
        let data = try source.exportBackup()
        let restored = TabStore(cloud: false, inMemory: true)
        try restored.importBackup(data)
        XCTAssertEqual(restored.tabs.first?.name, source.tabs.first?.name)
        XCTAssertEqual(restored.tabs.first?.total, source.tabs.first?.total)
        XCTAssertEqual(restored.tabs.first?.people.map(\.name).sorted(), source.tabs.first?.people.map(\.name).sorted())
        XCTAssertEqual(restored.tabs.first?.transfers.map(\.cents), source.tabs.first?.transfers.map(\.cents))
        XCTAssertNotEqual(restored.tabs.first?.id, source.tabs.first?.id)
        let expected = restored.tabs
        XCTAssertThrowsError(try restored.importBackup(data))
        XCTAssertEqual(restored.tabs, expected)
    }

    func testInvalidRestoreIsAtomic() throws {
        let source = TabStore(cloud: false, inMemory: true)
        _ = try fixture(source)
        var invalid = source.tabs[0]
        invalid.expenses[0].shares = [:]
        let data = try JSONEncoder().encode(Backup(version: 1, tabs: [source.tabs[0], invalid]))
        let target = TabStore(cloud: false, inMemory: true)
        XCTAssertThrowsError(try target.importBackup(data))
        XCTAssertTrue(target.tabs.isEmpty)
        XCTAssertEqual(try target.context.count(for: NSFetchRequest<SUTab>(entityName: "SUTab")), 0)
    }

    func testStaleExpenseEditAndDeleteAreRejected() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try fixture(store)
        let original = store.tabs[0].expenses[0]
        var updated = original; updated.title = "Updated elsewhere"
        try store.save(updated, tabID: id, original: original)
        var stale = original; stale.title = "Stale form"
        XCTAssertThrowsError(try store.save(stale, tabID: id, original: original))
        XCTAssertThrowsError(try store.deleteExpense(original, tabID: id))
        XCTAssertEqual(store.tabs[0].expenses[0].title, updated.title)
    }

    func testStalePaymentCannotBeRecordedTwice() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try fixture(store)
        let payment = Settlement.smart(store.tabs[0])[0]
        try store.record(payment, tabID: id)
        XCTAssertThrowsError(try store.record(payment, tabID: id))
        let transfer = store.tabs[0].transfers[0]
        try store.undo(transfer, tabID: id)
        XCTAssertTrue(store.tabs[0].transfers.isEmpty)
        XCTAssertTrue(Settlement.smart(store.tabs[0]).contains(payment))
    }

    func testDeletingExpenseRetainsRecordedPayments() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try fixture(store)
        let expense = store.tabs[0].expenses[0]
        try store.record(Settlement.smart(store.tabs[0])[0], tabID: id)
        try store.deleteExpense(expense, tabID: id)
        XCTAssertTrue(store.tabs[0].expenses.isEmpty)
        XCTAssertEqual(store.tabs[0].transfers.count, 1)
    }

    func testInvalidExpenseCannotMutateStore() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try fixture(store)
        let expected = store.tabs
        let invalid = Expense(title: "", payer: UUID(), cents: 10, shares: [:], mode: .even)
        XCTAssertThrowsError(try store.save(invalid, tabID: id))
        XCTAssertEqual(store.tabs, expected)
    }

    func testCloudModelHasOptionalFieldsAndInverseRelationships() throws {
        let store = TabStore(cloud: false, inMemory: true)
        for entity in store.container.managedObjectModel.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty)
            for property in entity.properties {
                XCTAssertTrue(property.isOptional)
                if let relationship = property as? NSRelationshipDescription { XCTAssertNotNil(relationship.inverseRelationship) }
            }
        }
    }

    func testSimultaneousPaymentRecordsAreCountedOnceAndUndoRemovesBoth() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try fixture(store)
        let suggestion = Settlement.smart(store.tabs[0])[0]
        try store.record(suggestion, tabID: id)
        let transfer = store.tabs[0].transfers[0]
        let request = NSFetchRequest<SUTab>(entityName: "SUTab")
        let tab = try XCTUnwrap(store.context.fetch(request).first)
        let entry = SUEntry(context: store.context)
        var duplicate = transfer; duplicate.date = transfer.date.addingTimeInterval(1)
        entry.id = duplicate.id; entry.kind = "transfer"; entry.payload = try JSONEncoder().encode(duplicate); entry.tab = tab
        try store.context.save(); store.reload()
        XCTAssertEqual(store.tabs[0].transfers.count, 1)
        try store.undo(transfer, tabID: id)
        XCTAssertTrue(store.tabs[0].transfers.isEmpty)
        XCTAssertFalse(tab.entries!.contains { $0.kind == "transfer" })
    }

    func testRenameAndDeleteTabCascade() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try fixture(store)
        try store.rename(id, name: "Renamed")
        XCTAssertEqual(store.tabs[0].name, "Renamed")
        XCTAssertThrowsError(try store.rename(id, name: " "))
        try store.deleteTab(id)
        XCTAssertTrue(store.tabs.isEmpty)
        XCTAssertEqual(try store.context.count(for: NSFetchRequest<SUEntry>(entityName: "SUEntry")), 0)
    }

    func testSettlementCanExceedIndividualExpenseLimit() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try store.create(name: "Large tab", names: ["A", "B"])
        let people = store.tabs[0].people
        for _ in 0..<3 {
            try store.save(Expense(title: "Expense", payer: people[0].id, cents: Money.maximum,
                                   shares: [people[1].id: Money.maximum], mode: .personal), tabID: id)
        }
        try store.record(Settlement.smart(store.tabs[0])[0], tabID: id)
        XCTAssertTrue(store.dataReadable)
        XCTAssertTrue(Settlement.smart(store.tabs[0]).isEmpty)
        try store.tabs[0].validate()
    }
}
