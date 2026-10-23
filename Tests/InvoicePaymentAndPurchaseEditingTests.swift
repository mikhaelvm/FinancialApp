import XCTest
import SwiftData
@testable import Trackr
@testable import class Trackr.Category
@testable import class Trackr.Transaction

@MainActor final class InvoicePaymentAndPurchaseEditingTests: XCTestCase {
    private func date(_ month: Int, _ day: Int) -> Date {
        FinanceDate.calendar.date(from: DateComponents(year: 2025, month: month, day: day))!
    }
    private func card(_ context: ModelContext) throws -> CreditCard {
        let card = CreditCard(name: "Principal", limitCents: 100000, closingDay: 20, dueDay: 25)
        context.insert(card); try context.save(); return card
    }
    private func balance(_ context: ModelContext) throws -> Int64 {
        DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
            cards: try context.fetch(FetchDescriptor<CreditCard>()), subscriptions: [],
            payments: try context.fetch(FetchDescriptor<InvoicePayment>()), month: .now).balance
    }

    func testBackdatedPaymentUsesSelectedDateAndCannotBeRecordedTwice() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 12000, date: date(1, 1), installments: 1, card: card, category: nil)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(1, 31)).first)
        try model.pay(context: context, card: card, invoice: invoice, date: date(1, 24))
        XCTAssertEqual(card.payments.first?.date, date(1, 24))
        XCTAssertEqual(try balance(context), -12000)
        XCTAssertThrowsError(try model.pay(context: context, card: card, invoice: invoice, date: date(1, 24)))
        XCTAssertEqual(card.payments.count, 1)
        let january = DashboardViewModel().snapshot(transactions: [], cards: [card], subscriptions: [], payments: card.payments, month: date(1, 1))
        XCTAssertEqual(january.payments, 12000)
    }

    func testInvalidPaymentDatesDoNotChangeBalanceOrSavePayments() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 12000, date: date(1, 1), installments: 1, card: card, category: nil)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(1, 31)).first)
        XCTAssertThrowsError(try model.pay(context: context, card: card, invoice: invoice, date: date(1, 1)))
        let tomorrow = FinanceDate.calendar.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertThrowsError(try model.pay(context: context, card: card, invoice: invoice, date: tomorrow))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InvoicePayment>()), 0)
        XCTAssertEqual(try balance(context), 0)
    }

    func testDeletingPaymentReopensInvoiceAndReturnsCashWithoutDeletingPurchase() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 12000, date: date(1, 1), installments: 1, card: card, category: nil)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(1, 31)).first)
        try model.pay(context: context, card: card, invoice: invoice, date: date(1, 24))
        let payment = try XCTUnwrap(card.payments.first)
        try model.deletePayment(context: context, payment: payment)
        XCTAssertEqual(try balance(context), 0)
        XCTAssertEqual(card.transactions.count, 1)
        XCTAssertEqual(card.usedLimitCents, 12000)
        XCTAssertEqual(InvoiceEngine().invoices(for: card, through: date(1, 31)).first?.remainingCents, 12000)
    }

    func testPurchaseEditRedistributesExactCentsAndKeepsExistingInstallmentIdentities() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Original", amountCents: 10000, date: date(1, 1), installments: 2, card: card, category: nil)
        let original = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        let ids = original.transactions.map(\.id)
        try model.editPurchase(context: context, card: card, purchaseID: original.purchaseID, title: "Editada",
                               amountCents: 10001, date: date(2, 1), installments: 3, category: nil)
        let result = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        XCTAssertEqual(result.amountCents, 10001)
        XCTAssertEqual(result.transactions.map(\.amountCents), [3334, 3334, 3333])
        XCTAssertEqual(Array(result.transactions.prefix(2).map(\.id)), ids)
        XCTAssertEqual(result.purchaseID, original.purchaseID)
        XCTAssertEqual(result.title, "Editada")
        XCTAssertEqual(card.usedLimitCents, 10001)
        XCTAssertEqual(try balance(context), 0)
        try BackupService.snapshot(context: context).validate()
    }

    func testRemovingInstallmentsAndChangingDateRecalculatesInvoices() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 12000, date: date(1, 1), installments: 12, card: card, category: nil)
        let original = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        try model.editPurchase(context: context, card: card, purchaseID: original.purchaseID, title: "Compra",
                               amountCents: 12000, date: date(2, 1), installments: 1, category: nil)
        XCTAssertEqual(card.transactions.count, 1)
        let dates = InvoiceEngine().dates(for: date(2, 1), closingDay: 20, dueDay: 25)
        XCTAssertEqual(card.transactions.first?.invoiceDueDate, dates.due)
        XCTAssertEqual(card.transactions.first?.amountCents, 12000)
    }

    func testTitleOnlyEditPreservesHistoricalDatesAfterCardConfigurationChanges() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 10000, date: date(1, 1), installments: 2, card: card, category: nil)
        let original = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        let dates = original.transactions.map(\.invoiceDueDate)
        card.closingDay = 5; card.dueDay = 12; try context.save()
        try model.editPurchase(context: context, card: card, purchaseID: original.purchaseID, title: "Nome corrigido",
                               amountCents: 10000, date: date(1, 1), installments: 2, category: nil)
        XCTAssertEqual(original.transactions.map(\.invoiceDueDate), dates)
        XCTAssertTrue(original.transactions.allSatisfy { $0.title == "Nome corrigido" })
    }

    func testReducingAlreadyPaidPurchasePreservesCashOutflow() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 10000, date: date(1, 1), installments: 1, card: card, category: nil)
        let purchase = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(1, 31)).first)
        try model.pay(context: context, card: card, invoice: invoice, date: date(1, 24))
        try model.editPurchase(context: context, card: card, purchaseID: purchase.purchaseID, title: "Corrigida",
                               amountCents: 5000, date: date(1, 1), installments: 1, category: nil)
        XCTAssertEqual(try balance(context), -10000)
        XCTAssertEqual(card.usedLimitCents, 0)
        XCTAssertEqual(card.payments.reduce(0) { $0 + $1.amountCents }, 5000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).filter { $0.card == nil }.reduce(0) { $0 + $1.amountCents }, 5000)
        try BackupService.snapshot(context: context).validate()
    }

    func testOverLimitEditIsRejectedBeforeAnyMutation() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 10000, date: date(1, 1), installments: 1, card: card, category: nil)
        let purchase = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        XCTAssertThrowsError(try model.editPurchase(context: context, card: card, purchaseID: purchase.purchaseID, title: "Não salvar",
            amountCents: 100001, date: date(1, 1), installments: 2, category: nil))
        XCTAssertEqual(card.transactions.first?.title, "Compra")
        XCTAssertEqual(card.transactions.count, 1)
        XCTAssertEqual(card.usedLimitCents, 10000)
        XCTAssertFalse(context.hasChanges)
    }

    func testMovingPaidPurchaseToAnotherInvoiceMovesAllocationWithoutAnotherCashDebit() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 10000, date: date(1, 1), installments: 1, card: card, category: nil)
        let purchase = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(1, 31)).first)
        try model.pay(context: context, card: card, invoice: invoice, date: date(1, 24))
        let paymentID = try XCTUnwrap(card.payments.first?.id)
        try model.editPurchase(context: context, card: card, purchaseID: purchase.purchaseID, title: "Compra",
            amountCents: 10000, date: date(2, 1), installments: 1, category: nil)
        XCTAssertEqual(try balance(context), -10000)
        XCTAssertEqual(card.usedLimitCents, 0)
        XCTAssertEqual(card.payments.first?.id, paymentID)
        XCTAssertEqual(card.payments.first?.date, date(1, 24))
        XCTAssertEqual(card.payments.first?.invoiceDueDate, card.transactions.first?.invoiceDueDate)
        XCTAssertEqual(InvoiceEngine().invoices(for: card, through: date(3, 31)).reduce(0) { $0 + $1.remainingCents }, 0)
    }

    func testSplittingAlreadyPaidPurchaseKeepsAllInstallmentsPaidAndCashUnchanged() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 10000, date: date(1, 1), installments: 1, card: card, category: nil)
        let purchase = try XCTUnwrap(CardPurchaseService.groups(for: card).first)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(1, 31)).first)
        try model.pay(context: context, card: card, invoice: invoice, date: date(1, 24))
        try model.editPurchase(context: context, card: card, purchaseID: purchase.purchaseID, title: "Compra",
            amountCents: 10000, date: date(2, 1), installments: 2, category: nil)
        XCTAssertEqual(try balance(context), -10000)
        XCTAssertEqual(card.payments.count, 2)
        XCTAssertEqual(card.payments.reduce(0) { $0 + $1.amountCents }, 10000)
        XCTAssertEqual(card.usedLimitCents, 0)
        XCTAssertTrue(card.payments.allSatisfy { $0.date == date(1, 24) })
        XCTAssertEqual(InvoiceEngine().invoices(for: card, through: date(4, 30)).reduce(0) { $0 + $1.remainingCents }, 0)
        try BackupService.snapshot(context: context).validate()
    }

    func testEditingRecurringChargeKeepsDeduplicationKeyAndDoesNotEditFutureSubscription() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try self.card(context), model = CreditCardViewModel()
        let sub = Subscription(title: "Serviço", amountCents: 1000, cycle: .monthly, nextRenewalDate: date(2, 1), category: nil, card: card)
        context.insert(sub)
        let dates = InvoiceEngine().dates(for: date(1, 1), closingDay: 20, dueDay: 25)
        let charge = Transaction(title: "Serviço", amountCents: 1000, kind: .expense, date: date(1, 1), card: card,
            invoiceDueDate: dates.due, invoiceClosingDate: dates.closing, subscription: sub, recurrenceKey: sub.scheduleID.uuidString + ":0")
        context.insert(charge); try context.save()
        let key = charge.recurrenceKey
        try model.editPurchase(context: context, card: card, purchaseID: charge.purchaseID, title: "Cobrança corrigida",
            amountCents: 800, date: date(1, 1), installments: 1, category: nil)
        XCTAssertEqual(charge.recurrenceKey, key)
        XCTAssertEqual(sub.title, "Serviço"); XCTAssertEqual(sub.amountCents, 1000)
        XCTAssertThrowsError(try model.editPurchase(context: context, card: card, purchaseID: charge.purchaseID, title: "Serviço",
            amountCents: 800, date: date(1, 1), installments: 2, category: nil))
    }
}
