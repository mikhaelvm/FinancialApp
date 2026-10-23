import XCTest
import SwiftData
@testable import Trackr
@testable import class Trackr.Category

@MainActor
final class BackupServiceTests: XCTestCase {
    func testCompleteBackupRestoresRelationshipsAndDoesNotDuplicateOnSecondImport() throws {
        let source = try Persistence.makeContainer(inMemory: true)
        let context = source.mainContext
        try Persistence.seed(context: context)
        let category = try XCTUnwrap(try context.fetch(FetchDescriptor<Category>()).first { $0.name == "Alimentação" })
        category.colorName = "pink"
        let card = CreditCard(name: "Principal", limitCents: 500_000, closingDay: 25, dueDay: 5)
        context.insert(card)
        context.insert(Transaction(title: "Receita", amountCents: 500_000, kind: .income, date: .now))
        let purchaseDate = FinanceDate.calendar.date(from: DateComponents(year: 2025, month: 1, day: 20))!
        try CreditCardViewModel().purchase(context: context, title: "Compra", amountCents: 120_000, date: purchaseDate,
                                           installments: 10, card: card, category: category)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: .now).first)
        context.insert(InvoicePayment(card: card, invoiceDueDate: invoice.dueDate, date: .now, amountCents: 12_000))
        let subscription = Subscription(title: "Serviço", amountCents: 3000, cycle: .monthly,
                                        nextRenewalDate: FinanceDate.monthOffset(2, from: .now), category: category, card: card)
        context.insert(subscription)
        let bill = ScheduledPayment(title: "Conta", amountCents: 10_000, dueDate: .now, categoryID: category.id)
        context.insert(bill)
        try context.save()
        try ScheduledPaymentViewModel().pay(bill, context: context)
        let original = try BackupService.snapshot(context: context)
        let decoded = try BackupService.decode(BackupService.encode(original))

        let destination = try Persistence.makeContainer(inMemory: true)
        // Existing seeded categories have different IDs; all references must be remapped by name.
        try Persistence.seed(context: destination.mainContext)
        XCTAssertGreaterThan(try BackupService.restore(decoded, context: destination.mainContext), 0)
        XCTAssertEqual(try BackupService.restore(decoded, context: destination.mainContext), 0)
        let restoredCards = try destination.mainContext.fetch(FetchDescriptor<CreditCard>())
        let restored = try XCTUnwrap(restoredCards.first)
        XCTAssertEqual(restored.id, card.id)
        XCTAssertEqual(restored.transactions.count, 10)
        XCTAssertEqual(restored.payments.count, 1)
        XCTAssertEqual(restored.usedLimitCents, card.usedLimitCents)
        let restoredBill = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<ScheduledPayment>()).first)
        let restoredCategory = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<Category>()).first { $0.name == "Alimentação" })
        XCTAssertTrue(restoredBill.isPaid)
        XCTAssertEqual(restoredBill.categoryID, restoredCategory.id)
        XCTAssertEqual(restoredCategory.colorName, "pink")
        XCTAssertEqual(restoredBill.paidTransactionID, bill.paidTransactionID)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Transaction>()), original.transactions.count)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Subscription>()).first?.scheduleID, subscription.scheduleID)
    }

    func testExistingEditsWinWhenMergingAnOldBackup() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let transaction = Transaction(title: "Original", amountCents: 100, kind: .income, date: .now)
        context.insert(transaction); try context.save()
        let backup = try BackupService.snapshot(context: context)
        transaction.title = "Alterado depois do backup"; transaction.amountCents = 200; try context.save()
        XCTAssertEqual(try BackupService.restore(backup, context: context), 0)
        XCTAssertEqual(transaction.title, "Alterado depois do backup")
        XCTAssertEqual(transaction.amountCents, 200)
    }

    func testUnknownVersionAndBrokenReferencesAreRejectedBeforeSaving() throws {
        let source = try Persistence.makeContainer(inMemory: true)
        source.mainContext.insert(Transaction(title: "Receita", amountCents: 100, kind: .income, date: .now))
        try source.mainContext.save()
        let data = try BackupService.encode(BackupService.snapshot(context: source.mainContext))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 999
        XCTAssertThrowsError(try BackupService.decode(JSONSerialization.data(withJSONObject: object)))
        object["formatVersion"] = 1
        var transactions = try XCTUnwrap(object["transactions"] as? [[String: Any]])
        transactions[0]["categoryID"] = UUID().uuidString
        object["transactions"] = transactions
        XCTAssertThrowsError(try BackupService.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testCSVPreservesNumericExpenseSignsAndEscapesSpreadsheetFormulas() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        container.mainContext.insert(Transaction(title: "=SUM(A1)", amountCents: 12000, kind: .expense, date: .now))
        try container.mainContext.save()
        let text = try XCTUnwrap(String(data: try BackupService.csv(context: container.mainContext), encoding: .utf8))
        XCTAssertTrue(text.contains("\"'=SUM(A1)\""))
        XCTAssertTrue(text.contains("\"-120,00\""))
    }

    func testStatementFingerprintSurvivesBackupRestoration() throws {
        let source = try Persistence.makeContainer(inMemory: true)
        let row = StatementRow(id: "statement:stable", date: FinanceDate.day(.now), title: "Compra", signedCents: -100)
        XCTAssertEqual(try StatementImportService.commit([row], context: source.mainContext), 1)
        let data = try BackupService.encode(BackupService.snapshot(context: source.mainContext))
        let target = try Persistence.makeContainer(inMemory: true)
        _ = try BackupService.restore(BackupService.decode(data), context: target.mainContext)
        XCTAssertEqual(try StatementImportService.commit([row], context: target.mainContext), 0)
    }
}
