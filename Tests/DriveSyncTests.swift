import XCTest
import SwiftData
@testable import Trackr
@testable import class Trackr.Category

@MainActor final class DriveSyncTests: XCTestCase {
    private func empty() -> TrackrBackup {
        TrackrBackup(categories: [], cards: [], subscriptions: [], transactions: [], payments: [], scheduled: [], dismissedPayments: [])
    }
    private func snapshot(_ context: ModelContext) throws -> [String: Data] {
        try DriveSyncState.index(BackupService.snapshot(context: context))
    }

    func testOfflineEditsToDifferentRecordsMergeAndConverge() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        try phone.capture(["a": Data("one".utf8), "b": Data("two".utf8)], baseline: nil)
        try tablet.merge(phone)
        let baseline = ["a": Data("one".utf8), "b": Data("two".utf8)]
        try phone.capture(["a": Data("edited phone".utf8), "b": baseline["b"]!], baseline: baseline)
        try tablet.capture(["a": baseline["a"]!, "b": Data("edited tablet".utf8)], baseline: baseline)
        try phone.merge(tablet); try tablet.merge(phone)
        XCTAssertEqual(phone.records, tablet.records)
        XCTAssertEqual(phone.records["a"]?.payload, Data("edited phone".utf8))
        XCTAssertEqual(phone.records["b"]?.payload, Data("edited tablet".utf8))
    }

    func testDeletionSurvivesUnchangedOfflineDeviceAndRepeatedMerges() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        let original = ["a": Data("value".utf8)]
        try phone.capture(original, baseline: nil); try tablet.merge(phone)
        try phone.capture([:], baseline: original)
        try tablet.merge(phone)
        try tablet.capture(original, baseline: original)
        try phone.merge(tablet); try tablet.merge(phone)
        XCTAssertNotNil(tablet.records["a"])
        XCTAssertNil(tablet.records["a"]?.payload)
        XCTAssertEqual(phone.records, tablet.records)
    }

    func testConcurrentSameRecordResolutionIsDeterministicAndOrderIndependent() throws {
        var a = DriveSyncDocument(), b = DriveSyncDocument()
        try a.capture(["row": Data("a".utf8)], baseline: nil)
        try b.capture(["row": Data("b".utf8)], baseline: nil)
        let originalA = a, originalB = b
        try a.merge(originalB); try b.merge(originalA)
        XCTAssertEqual(a.records, b.records)
        try a.merge(originalA); try a.merge(originalB)
        XCTAssertEqual(a.records, b.records)
    }

    func testRemoteDeletionWinsOverOfflineEditOfTheDeletedRecord() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        let baseline = ["row": Data("original".utf8)]
        try phone.capture(baseline, baseline: nil); try tablet.merge(phone)
        try phone.capture([:], baseline: baseline); try tablet.merge(phone)
        try tablet.capture(["row": Data("offline edit".utf8)], baseline: baseline)
        XCTAssertNil(tablet.records["row"]?.payload)
    }

    func testFirstConnectionImportsCloudWithoutDeletingMissingLocalRecords() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        try phone.capture(["cloud": Data("cloud".utf8)], baseline: nil)
        try tablet.merge(phone)
        try tablet.capture(["local": Data("local".utf8)], baseline: nil)
        XCTAssertEqual(tablet.records.count, 2)
        XCTAssertNotNil(tablet.records["cloud"]?.payload)
    }

    func testNewInstallationCannotResurrectKnownCloudDeletion() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        let stale = ["row": Data("stale".utf8)]
        try phone.capture(stale, baseline: nil); try phone.capture([:], baseline: stale)
        try tablet.merge(phone); try tablet.capture(stale, baseline: nil)
        XCTAssertNil(tablet.records["row"]?.payload)
    }

    func testDefaultsAndAutomaticChargesHaveSameIdentityOnBothDevices() throws {
        let phone = try Persistence.makeContainer(inMemory: true)
        let tablet = try Persistence.makeContainer(inMemory: true)
        let date = FinanceDate.day(.now)
        for context in [phone.mainContext, tablet.mainContext] {
            let category = Category(name: "Moradia", symbol: "house.fill", colorName: "blue")
            context.insert(category)
            context.insert(Transaction(title: "Internet", amountCents: 9990, kind: .expense, date: date,
                                       category: category, recurrenceKey: "shared-schedule:0"))
            try context.save()
        }
        XCTAssertEqual(try snapshot(phone.mainContext), try snapshot(tablet.mainContext))
    }

    func testMergedSnapshotAppliesEditsAndDeletionsAndKeepsObjectReferences() throws {
        let phone = try Persistence.makeContainer(inMemory: true)
        let tablet = try Persistence.makeContainer(inMemory: true)
        let source = Transaction(title: "Original", amountCents: 100, kind: .income, date: .now)
        phone.mainContext.insert(source); try phone.mainContext.save()
        var state = DriveSyncState()
        try state.document.capture(snapshot(phone.mainContext), baseline: nil)
        try DriveSyncPersistence.apply(state.materialize(), context: tablet.mainContext)
        let target = try XCTUnwrap(try tablet.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        let originalBaseline = try snapshot(phone.mainContext)
        source.title = "Editado"; source.amountCents = 250; try phone.mainContext.save()
        try state.document.capture(snapshot(phone.mainContext), baseline: originalBaseline)
        try DriveSyncPersistence.apply(state.materialize(), context: tablet.mainContext)
        XCTAssertEqual(target.title, "Editado")
        XCTAssertEqual(target.amountCents, 250)
        let editedBaseline = try snapshot(phone.mainContext)
        phone.mainContext.delete(source); try phone.mainContext.save()
        try state.document.capture(snapshot(phone.mainContext), baseline: editedBaseline)
        try DriveSyncPersistence.apply(state.materialize(), context: tablet.mainContext)
        XCTAssertEqual(try tablet.mainContext.fetchCount(FetchDescriptor<Transaction>()), 0)
    }

    func testScheduledReceiptNormalizationKeepsPaidRelationshipAndNoDuplicate() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = ScheduledPayment(title: "Energia", amountCents: 10000, dueDate: .now)
        context.insert(bill); try context.save()
        try ScheduledPaymentViewModel().pay(bill, context: context)
        var state = DriveSyncState()
        try state.document.capture(snapshot(context), baseline: nil)
        let backup = try state.materialize()
        try DriveSyncPersistence.apply(backup, context: context)
        try DriveSyncPersistence.apply(backup, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertEqual(bill.paidTransactionID, backup.transactions.first?.id)
        XCTAssertTrue(bill.isPaid)
    }

    func testDismissalAndReactivationPropagateInBothDirections() throws {
        var state = DriveSyncState()
        var backup = empty(); backup.dismissedPayments = ["invoice:test"]
        let baseline = try DriveSyncState.index(backup)
        try state.document.capture(baseline, baseline: nil)
        XCTAssertEqual(try state.materialize().dismissedPayments, ["invoice:test"])
        backup.dismissedPayments = []
        try state.document.capture(DriveSyncState.index(backup), baseline: baseline)
        XCTAssertEqual(try state.materialize().dismissedPayments, [])
    }

    func testDeletedCardCannotLeaveOrphanChargeOrEraseConcurrentCashPayment() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let card = CreditCard(name: "Cartão", limitCents: 100000, closingDay: 5, dueDay: 12)
        context.insert(card)
        context.insert(Transaction(title: "Compra", amountCents: 5000, kind: .expense, date: .now, card: card,
                                   invoiceDueDate: .now, invoiceClosingDate: .now))
        context.insert(InvoicePayment(card: card, invoiceDueDate: .now, date: .now, amountCents: 5000))
        try context.save()
        var state = DriveSyncState()
        try state.document.capture(snapshot(context), baseline: nil)
        state.document.write(["cards|" + card.id.uuidString: nil])
        let backup = try state.materialize()
        XCTAssertTrue(backup.cards.isEmpty); XCTAssertTrue(backup.payments.isEmpty)
        XCTAssertEqual(backup.transactions.count, 1)
        XCTAssertNil(backup.transactions.first?.cardID)
        XCTAssertEqual(backup.transactions.first?.amountCents, 5000)
        // The repair is persisted in the document and survives another merge/apply.
        XCTAssertEqual(try DriveSyncState.index(state.materialize()), try DriveSyncState.index(backup))
    }

    func testMalformedRemoteStateFailsBeforeChangingDatabase() throws {
        var state = DriveSyncState()
        state.document.formatVersion = 99
        var local = DriveSyncDocument()
        XCTAssertThrowsError(try local.merge(state.document))
        state = DriveSyncState()
        state.document.write(["payments|" + UUID().uuidString: Data("{}".utf8)])
        XCTAssertThrowsError(try state.materialize())
    }

    func testAutomaticRenewalDoesNotUndoRemotePauseOrRewindProgress() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let sub = Subscription(title: "Internet", amountCents: 1000, cycle: .monthly, nextRenewalDate: .now, category: nil, card: nil)
        context.insert(sub); try context.save()
        let baseline = try snapshot(context)
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        try phone.capture(baseline, baseline: nil); try tablet.merge(phone)
        sub.isActive = false; sub.nextOccurrenceIndex = 3
        sub.nextRenewalDate = FinanceDate.monthOffset(3, from: sub.anchorDate)
        try context.save()
        try phone.capture(snapshot(context), baseline: baseline)
        sub.isActive = true; sub.nextOccurrenceIndex = 1
        sub.nextRenewalDate = FinanceDate.monthOffset(1, from: sub.anchorDate)
        try context.save()
        try tablet.merge(phone)
        try tablet.capture(snapshot(context), baseline: baseline)
        var state = DriveSyncState(); state.document = tablet
        let result = try XCTUnwrap(try state.materialize().subscriptions.first)
        XCTAssertFalse(result.isActive)
        XCTAssertEqual(result.nextOccurrenceIndex, 3)
    }

    func testRollbackReplacesEditsAndRemovesRecordsCreatedAfterBackup() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let transaction = Transaction(title: "Versão antiga", amountCents: 100, kind: .income, date: .now)
        context.insert(transaction); try context.save()
        let oldBackup = try BackupService.snapshot(context: context)
        transaction.title = "Versão recente"; transaction.amountCents = 200
        context.insert(Transaction(title: "Depois do backup", amountCents: 300, kind: .income, date: .now))
        try context.save()
        var state = DriveSyncState()
        try state.document.capture(snapshot(context), baseline: nil)
        state.document.replace(with: try DriveSyncState.index(oldBackup))
        try DriveSyncPersistence.apply(state.materialize(), context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertEqual(transaction.title, "Versão antiga")
        XCTAssertEqual(transaction.amountCents, 100)
        XCTAssertEqual(try snapshot(context), try DriveSyncState.index(oldBackup))
    }

    func testOfflineDeviceAcceptsRollbackWithoutReuploadingItsOldGenerationEdits() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncState()
        let original = ["row": Data("original".utf8)]
        try phone.capture(original, baseline: nil)
        try tablet.document.merge(phone); tablet.baseline = original
        let previous = tablet.document.replacement
        // The tablet is offline while the phone rolls back to an empty snapshot.
        phone.replace(with: [:])
        try tablet.document.merge(phone)
        let offline = ["row": Data("offline edit".utf8), "new": Data("offline new row".utf8)]
        try tablet.captureLocal(offline, previousReplacement: previous)
        XCTAssertTrue(tablet.document.records.isEmpty)
        XCTAssertEqual(tablet.document.replacement, phone.replacement)
        try phone.merge(tablet.document)
        XCTAssertTrue(phone.records.isEmpty)
    }

    func testHighRevisionFromOldGenerationCannotUndoReplacementAndNewEditsStillWork() throws {
        var phone = DriveSyncDocument(), stale = DriveSyncDocument()
        try phone.capture(["row": Data("old".utf8)], baseline: nil); try stale.merge(phone)
        phone.replace(with: ["row": Data("restored".utf8)])
        for index in 0..<20 { stale.write(["row": Data("offline \(index)".utf8)]) }
        try phone.merge(stale)
        XCTAssertEqual(phone.records["row"]?.payload, Data("restored".utf8))
        let restored = ["row": Data("restored".utf8)]
        try phone.capture(["row": Data("new edit after restore".utf8)], baseline: restored)
        try stale.merge(phone)
        XCTAssertEqual(stale.records, phone.records)
        XCTAssertEqual(stale.replacement, phone.replacement)
    }

    func testConcurrentRollbacksResolveDeterministically() throws {
        var phone = DriveSyncDocument(), tablet = DriveSyncDocument()
        phone.replace(with: ["row": Data("phone backup".utf8)])
        tablet.replace(with: ["row": Data("tablet backup".utf8)])
        let originalPhone = phone, originalTablet = tablet
        try phone.merge(originalTablet); try tablet.merge(originalPhone)
        XCTAssertEqual(phone.replacement, tablet.replacement)
        XCTAssertEqual(phone.records, tablet.records)
    }

    func testRollbackCanRewindRecurrenceProgressToTheBackupVersion() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let subscription = Subscription(title: "Serviço", amountCents: 1000, cycle: .monthly, nextRenewalDate: .now, category: nil, card: nil)
        context.insert(subscription); try context.save()
        let backup = try BackupService.snapshot(context: context)
        subscription.nextOccurrenceIndex = 8
        subscription.nextRenewalDate = FinanceDate.monthOffset(8, from: subscription.anchorDate)
        try context.save()
        var phone = DriveSyncState(), tablet = DriveSyncDocument()
        try phone.document.capture(snapshot(context), baseline: nil); try tablet.merge(phone.document)
        phone.document.replace(with: try DriveSyncState.index(backup))
        try tablet.merge(phone.document)
        phone.document = tablet
        XCTAssertEqual(try phone.materialize().subscriptions.first?.nextOccurrenceIndex, 0)
    }

    func testSyncV1RemainsReadableAndInvalidReplacementMetadataIsRejected() throws {
        var legacy = DriveSyncDocument()
        try legacy.capture(["row": Data("v1".utf8)], baseline: nil)
        XCTAssertEqual(legacy.formatVersion, 1)
        let decoded = try JSONDecoder().decode(DriveSyncDocument.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.replacement)
        var updated = DriveSyncDocument()
        try updated.merge(decoded)
        XCTAssertEqual(updated.records, legacy.records)
        legacy.replacement = .init(revision: 9, writer: UUID())
        XCTAssertThrowsError(try updated.merge(legacy))
    }
}
