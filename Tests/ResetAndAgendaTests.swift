import XCTest
import SwiftData
@testable import Trackr
@testable import class Trackr.Category

@MainActor
final class ResetAndAgendaTests: XCTestCase {
    func testDeletingPaidScheduleCanKeepOrRemoveTheCashExpense() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let model = ScheduledPaymentViewModel()
        let first = ScheduledPayment(title: "Energia", amountCents: 12000, dueDate: .now)
        context.insert(first); try context.save()
        try model.pay(first, context: context)
        try model.delete(first, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledPayment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
        let second = ScheduledPayment(title: "Internet", amountCents: 8000, dueDate: .now)
        context.insert(second); try context.save()
        try model.pay(second, context: context)
        try model.delete(second, context: context, removeRecordedExpense: true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).first?.title, "Energia")
    }

    func testResetClearsAllFinancialModelsRestoresCategoriesAndPreferencesAndIsIdempotent() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        try Persistence.seed(context: context)
        let category = try XCTUnwrap(try context.fetch(FetchDescriptor<Category>()).first { $0.name == "Streaming" })
        category.colorName = "pink"; category.symbol = "star"
        context.insert(Category(name: "Personalizada", symbol: "star", colorName: "pink"))
        let card = CreditCard(name: "Banco", limitCents: 100000, closingDay: 20, dueDay: 25)
        context.insert(card)
        context.insert(Transaction(title: "Compra", amountCents: 1200, kind: .expense, date: .now, category: category))
        context.insert(Subscription(title: "Streaming", amountCents: 1000, cycle: .monthly, nextRenewalDate: .now, category: category, card: card))
        context.insert(InvoicePayment(card: card, invoiceDueDate: .now, date: .now, amountCents: 100))
        context.insert(ScheduledPayment(title: "Conta", amountCents: 100, dueDate: .now))
        try context.save()
        let suite = "TrackrTests.Reset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pink", forKey: "trackr.accent")
        defaults.set(true, forKey: "reminders.enabled")
        defaults.set("retained", forKey: "unrelated")
        for revision in 1...2 {
            try AppResetService.reset(context: context, defaults: defaults)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CreditCard>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Subscription>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<InvoicePayment>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledPayment>()), 0)
            let categories = try context.fetch(FetchDescriptor<Category>())
            XCTAssertEqual(categories.count, 9)
            XCTAssertEqual(categories.first { $0.name == "Streaming" }?.colorName, "purple")
            XCTAssertNil(defaults.object(forKey: "trackr.accent"))
            XCTAssertNil(defaults.object(forKey: "reminders.enabled"))
            XCTAssertEqual(defaults.integer(forKey: "trackr.resetRevision"), revision)
            XCTAssertEqual(defaults.string(forKey: "unrelated"), "retained")
        }
    }

    func testPDFRowsRemainUnselectedUntilReviewed() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let parsed = try PDFStatementReader.parseText("02/01/2025 Padaria 10,00 D")
        var rows = try StatementImportService.prepare(parsed.rows, context: container.mainContext)
        XCTAssertFalse(rows[0].selected)
        XCTAssertEqual(try StatementImportService.commit(rows, context: container.mainContext), 0)
        rows[0].selected = true
        XCTAssertEqual(try StatementImportService.commit(rows, context: container.mainContext), 1)
        XCTAssertTrue(try StatementImportService.prepare(parsed.rows, context: container.mainContext)[0].isDuplicate)
    }
}
