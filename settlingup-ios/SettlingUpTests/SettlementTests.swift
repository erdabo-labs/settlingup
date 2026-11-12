import XCTest
import CoreData
import UIKit
import CloudKit
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

final class WebParityTests: XCTestCase {
    func testSmartPaymentTiesUseWebsitePersonOrder() {
        let p = [Person(name: "First creditor"), Person(name: "Second creditor"), Person(name: "Debtor")]
        let tab = TabSnapshot(name: "Ties", people: p, expenses: [
            Expense(title: "One", payer: p[0].id, cents: 1000, shares: [p[2].id: 1000], mode: .personal),
            Expense(title: "Two", payer: p[1].id, cents: 1000, shares: [p[2].id: 1000], mode: .personal)
        ])
        XCTAssertEqual(Settlement.displayedPayments(tab), [
            .init(from: p[2].id, to: p[0].id, cents: 1000),
            .init(from: p[2].id, to: p[1].id, cents: 1000)
        ])
    }
    func testWebsiteTabCodesAndExistingLinksStayOnWebsite() throws {
        XCTAssertEqual(try WebsiteTab.url(for: " Ab12Cd ").absoluteString, "https://www.settlingup.app/t/Ab12Cd")
        for link in ["https://settlingup.app/t/Ab12Cd?p=e", "https://www.settlingup.app/#v2.abc_DEF-123"] {
            XCTAssertEqual(try WebsiteTab.url(for: link).absoluteString, link)
        }
        for invalid in ["", "abc", "a/bcd", "https://settlingup.app.evil.example/t/Ab12Cd", "https://evil.example/t/Ab12Cd", "https://user@settlingup.app/t/Ab12Cd", "javascript:alert(1)"] {
            XCTAssertThrowsError(try WebsiteTab.url(for: invalid))
        }
    }
    func testCustomRoundingMatchesActualWebsiteCode() throws {
        // Evaluated by executing index.html's addExpense custom calculation unchanged.
        let cases: [([Int], Int, Int, [Int])] = [
            ([1000, 1000, 1000], 2, 0, [1000, 1001, 1001]),
            ([1, 1, 1, 1], 2, 0, [0, 2, 2, 2]),
            ([1, 2, 3], 1, 1, [1, 3, 4]),
            ([1234, 5678, 910], 123, 777, [1376, 6331, 1015]),
            ([4600, 5800, 5200, 4600, 5400, 5400], 2480, 6200, [5888, 7424, 6656, 5888, 6912, 6912])
        ]
        for (values, tax, tip, expected) in cases {
            let ids = values.map { _ in UUID() }
            let shares = try Settlement.custom(bases: Dictionary(uniqueKeysWithValues: zip(ids, values)), tax: tax, tip: tip, people: ids)
            XCTAssertEqual(ids.map { shares[$0, default: 0] }, expected)
            XCTAssertEqual(shares.values.reduce(0, +), values.reduce(0, +) + tax + tip)
        }
    }

    func testTinyCustomSharesNeverLoseMoneyToNegativeRoundingCorrection() throws {
        let ids = (0..<100).map { _ in UUID() }
        for count in 2...100 {
            for extra in 0...100 {
                let included = Array(ids.prefix(count))
                let shares = try Settlement.custom(bases: Dictionary(uniqueKeysWithValues: included.map { ($0, 1) }), tax: extra, tip: 0, people: included)
                XCTAssertEqual(shares.values.reduce(0, +), count + extra)
                XCTAssertTrue(shares.values.allSatisfy { $0 > 0 })
            }
        }
    }

    func testDecimalPadAmountsAllowOmittedLeadingZeroAndTrailingPoint() throws {
        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(try Money.parse(separator + "50"), 50)
        XCTAssertEqual(try Money.parse("12" + separator), 1200)
        XCTAssertThrowsError(try Money.parse(separator))
        XCTAssertThrowsError(try Money.parse(separator + "001"))
    }
    func testOriginalWebsiteDemoBalancesMatchToTheCent() throws {
        // Expected values were evaluated using index.html's computeBalances and
        // computePersonShare against the unmodified settlingup-demos.js scenarios.
        let expected = [
            [118796, -33253, -14503, 41746, 58196, -34404, -27504, -21004, 7496, -7804, -41304, -46458],
            [334887, -36913, -8138, -35338, -68112, -55612, -59737, -71037],
            [-6828, 24265, -5148, -680, -105, -11504]
        ]
        XCTAssertEqual(DemoScenario.all.count, 3)
        for (index, demo) in DemoScenario.all.enumerated() {
            let tab = try demo.snapshot()
            let balances = Settlement.balances(tab)
            XCTAssertEqual(tab.people.map { balances[$0.id, default: 0] }, expected[index], demo.title)
            var settled = tab
            settled.transfers = Settlement.displayedPayments(tab).map { Transfer(from: $0.from, to: $0.to, cents: $0.cents) }
            XCTAssertTrue(Settlement.balances(settled).values.allSatisfy { $0 == 0 }, demo.title)
        }
    }

    func testEvenRemainderRotatesAcrossExpenses() throws {
        let ids = (0..<3).map { _ in UUID() }
        var totals = [UUID: Int]()
        for offset in 0..<3 {
            let shares = try Settlement.even(cents: 1000, people: ids, rotation: offset)
            XCTAssertEqual(shares.values.reduce(0, +), 1000)
            for (id, cents) in shares { totals[id, default: 0] += cents }
        }
        XCTAssertEqual(ids.map { totals[$0] }, [1000, 1000, 1000])
    }

    func testPaidCardsRemainVisibleInBothStrategies() {
        let a = Person(name: "Alex"), b = Person(name: "Sam"), c = Person(name: "Jo")
        var tab = TabSnapshot(name: "Web example", people: [a, b, c], expenses: [
            Expense(title: "Sam paid for Alex", payer: b.id, cents: 2500, shares: [a.id: 2500], mode: .personal),
            Expense(title: "Jo paid for Sam", payer: c.id, cents: 2500, shares: [b.id: 2500], mode: .personal)
        ])
        let smart = Settlement.displayedPayments(tab)
        XCTAssertEqual(smart, [.init(from: a.id, to: c.id, cents: 2500)])
        XCTAssertEqual(Settlement.displayedPayments(tab, direct: true).count, 2)
        tab.transfers.append(Transfer(from: a.id, to: c.id, cents: 2500))
        XCTAssertEqual(Settlement.displayedPayments(tab), smart)
        XCTAssertNotNil(Settlement.markedPayment(smart[0], in: tab))
        XCTAssertTrue(Settlement.balances(tab).values.allSatisfy { $0 == 0 })
    }

    func testCustomSplitExclusionAndTaxTip() throws {
        let a = UUID(), b = UUID()
        let shares = try Settlement.custom(bases: [a: 2000, b: 1000], tax: 240, tip: 600)
        XCTAssertEqual(shares, [a: 2560, b: 1280])
        XCTAssertEqual(shares.values.reduce(0, +), 3840)
    }
}

@MainActor
final class ParityPersistenceTests: XCTestCase {
    func testCustomEditingPreservesTaxTipBasesAndRecordedPaymentsOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TabStore(directory: directory, cloud: false)
        let id = try store.create(name: "Dinner", names: ["Alex", "Sam", "Jo"])
        let people = store.tabs[0].people.map(\.id)
        let bases = Dictionary(uniqueKeysWithValues: zip(people, [1234, 5678, 910]))
        let original = Expense(title: "Dinner", payer: people[0], cents: 8722,
                               shares: try Settlement.custom(bases: bases, tax: 123, tip: 777, people: people),
                               mode: .custom, tax: 123, tip: 777, bases: bases)
        try store.save(original, tabID: id)
        try store.record(Settlement.displayedPayments(store.tabs[0])[0], tabID: id)
        var edited = original
        edited.title = "Dinner receipt"
        edited.tip = 877; edited.cents += 100
        edited.shares = try Settlement.custom(bases: bases, tax: edited.tax, tip: edited.tip, people: people)
        try store.save(edited, tabID: id, original: original)
        let expected = store.tabs
        for persistent in store.container.persistentStoreCoordinator.persistentStores { try store.container.persistentStoreCoordinator.remove(persistent) }
        let reopened = TabStore(directory: directory, cloud: false)
        XCTAssertEqual(reopened.tabs, expected)
        XCTAssertEqual(reopened.tabs[0].expenses[0], edited)
        XCTAssertEqual(reopened.tabs[0].transfers.count, 1)
    }
    func testRemovingZeroSharePersonKeepsExpenseAndLibraryReadable() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try store.create(name: "Dinner", names: ["Alex", "Sam", "Jo"])
        let p = store.tabs[0].people
        let shares = try Settlement.custom(bases: [p[0].id: 1000, p[1].id: 0], tax: 100, tip: 200, people: p.map(\.id))
        let expense = Expense(title: "Dinner", payer: p[0].id, cents: 1300, shares: shares, mode: .custom, tax: 100, tip: 200, bases: [p[0].id: 1000, p[1].id: 0])
        try store.save(expense, tabID: id)
        try store.removePerson(p[1], tabID: id)
        XCTAssertTrue(store.dataReadable, store.error ?? "")
        XCTAssertEqual(store.tabs[0].people.map(\.name), ["Alex", "Jo"])
        XCTAssertEqual(store.tabs[0].expenses[0].shares, shares)
        XCTAssertEqual(store.tabs[0].expenses[0].bases, [p[0].id: 1000])
        try store.tabs[0].validate()
        XCTAssertNoThrow(try store.exportBackup())
    }

    func testNestedCloudDiagnosticsExposeServerFailureWithoutRecordKeys() {
        let inner = NSError(domain: CKErrorDomain, code: CKError.invalidArguments.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cannot create field CD_moveReceipt in production schema"])
        let partial = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue, userInfo: [CKPartialErrorsByItemIDKey: ["private-record-id": inner]])
        let multiple = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [NSMultipleUnderlyingErrorsKey: [partial]])
        let outer = NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: [NSDetailedErrorsKey: [multiple]])
        let detail = TabStore.describe(outer)
        XCTAssertTrue(detail.contains("CD_moveReceipt"))
        XCTAssertTrue(detail.contains("CKErrorDomain"))
        XCTAssertFalse(detail.contains("private-record-id"))
    }
    func testPeopleKeepEntryOrderAndRenameWithoutChangingSplits() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try store.create(name: "Dinner", names: ["Zoe", "Alex", "Sam"])
        XCTAssertEqual(store.tabs[0].people.map(\.name), ["Zoe", "Alex", "Sam"])
        let person = store.tabs[0].people[0]
        let expense = Expense(title: "Dinner", payer: person.id, cents: 1000, shares: [person.id: 1000], mode: .personal)
        try store.save(expense, tabID: id)
        try store.renamePerson(person, name: "Z", tabID: id)
        XCTAssertEqual(store.tabs[0].people[0].name, "Z")
        XCTAssertEqual(store.tabs[0].expenses[0], expense)
        XCTAssertThrowsError(try store.addPerson("alex", tabID: id))
    }

    func testDirectPaymentMarkAndUndo() throws {
        let store = TabStore(cloud: false, inMemory: true)
        let id = try store.create(name: "Trip", names: ["Alex", "Sam", "Jo"])
        let p = store.tabs[0].people
        try store.save(Expense(title: "One", payer: p[1].id, cents: 2500, shares: [p[0].id: 2500], mode: .personal), tabID: id)
        try store.save(Expense(title: "Two", payer: p[2].id, cents: 2500, shares: [p[1].id: 2500], mode: .personal), tabID: id)
        let payments = Settlement.displayedPayments(store.tabs[0], direct: true)
        for payment in payments { try store.record(payment, tabID: id) }
        XCTAssertTrue(Settlement.balances(store.tabs[0]).values.allSatisfy { $0 == 0 })
        XCTAssertEqual(Settlement.displayedPayments(store.tabs[0], direct: true), payments)
        try store.undo(store.tabs[0].transfers[0], tabID: id)
        XCTAssertEqual(store.tabs[0].transfers.count, 1)
    }

    func testOldPersonPayloadStillDecodes() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Original person\"}".utf8)
        let person = try JSONDecoder().decode(Person.self, from: data)
        XCTAssertEqual(person.id, id)
        XCTAssertNil(person.order)
    }

    func testRefreshImportsBackgroundInsertAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TabStore(directory: directory, cloud: false)
        let id = try store.create(name: "Before", names: ["Alex", "Sam"])
        let background = store.container.newBackgroundContext()
        try background.performAndWait {
            let tab = try XCTUnwrap(background.fetch(NSFetchRequest<SUTab>(entityName: "SUTab")).first)
            tab.name = "Imported change"
            try background.save()
        }
        store.refresh()
        XCTAssertEqual(store.tabs.first?.name, "Imported change")
        try background.performAndWait {
            let tab = try XCTUnwrap(background.fetch(NSFetchRequest<SUTab>(entityName: "SUTab")).first)
            background.delete(tab)
            try background.save()
        }
        store.refresh()
        XCTAssertFalse(store.tabs.contains { $0.id == id })
    }
}


@MainActor
final class BrandingTests: XCTestCase {
    func testOriginalBrandFontWeightsAreBundledAndRegistered() throws {
        for name in ["Outfit-Regular", "Outfit-SemiBold", "Outfit-Bold", "Outfit-ExtraBold", "JetBrainsMono-Regular"] {
            let font = try XCTUnwrap(UIFont(name: name, size: 20), "Missing bundled font: " + name)
            XCTAssertEqual(font.fontName, name)
        }
    }
}
