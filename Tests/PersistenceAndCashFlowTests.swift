import XCTest
import SwiftData
@testable import FinancialApp
// A scoped import selects our model over ObjectiveC.Category exposed by XCTest.
@testable import class FinancialApp.Category

@MainActor
final class PersistenceAndCashFlowTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        FinanceDate.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testSchemaSeedingIsIdempotent() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try Persistence.seed(context: container.mainContext)
        try Persistence.seed(context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Category>()), 9)
    }

    func testCategorySummaryKeepsCustomSymbolsAndColors() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let housing = Category(name: "Moradia", symbol: "house.fill", colorName: "blue")
        let other = Category(name: "Outros", symbol: "star.fill", colorName: "pink")
        context.insert(housing); context.insert(other)
        context.insert(Transaction(title: "Aluguel", amountCents: 250000, kind: .expense, date: .now, category: housing))
        context.insert(Transaction(title: "Serviço", amountCents: 2500, kind: .expense, date: .now, category: other))
        try context.save()
        let snapshot = DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
                                                     cards: [], subscriptions: [], payments: [], month: .now)
        XCTAssertEqual(snapshot.categories.map(\.symbol), ["house.fill", "star.fill"])
        XCTAssertEqual(snapshot.categories.map(\.colorName), ["blue", "pink"])
        other.symbol = "heart.fill"
        let updated = DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
                                                    cards: [], subscriptions: [], payments: [], month: .now)
        XCTAssertEqual(updated.categories.last?.symbol, "heart.fill")
    }

    func testPurchasePersistsInversesAndDatesAcrossTenMonths() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let card = CreditCard(name: "Principal", limitCents: 200_000, closingDay: 25, dueDay: 5)
        context.insert(card)
        try CreditCardViewModel().purchase(context: context, title: "Computador", amountCents: 120_000,
                                           date: date(2025, 1, 20), installments: 10, card: card, category: nil)
        XCTAssertEqual(card.transactions.count, 10)
        XCTAssertEqual(card.availableLimitCents, 80_000)
        let invoices = InvoiceEngine().invoices(for: card, through: date(2025, 12, 31))
        XCTAssertEqual(invoices.count, 10)
        XCTAssertEqual(invoices.first?.dueDate, date(2025, 2, 5))
        XCTAssertEqual(invoices.last?.dueDate, date(2025, 11, 5))
        XCTAssertEqual(invoices.flatMap(\.lines).map(\.installmentNumber), Array(1...10))
        XCTAssertEqual(Set(card.transactions.map(\.purchaseID)).count, 1)
        card.closingDay = 10
        XCTAssertEqual(card.transactions.compactMap(\.invoiceDueDate).min(), date(2025, 2, 5))
        XCTAssertThrowsError(try CreditCardViewModel().purchase(context: context, title: "Excesso", amountCents: 90_000,
                                                               date: date(2025, 1, 20), installments: 1, card: card, category: nil))
        XCTAssertEqual(card.transactions.count, 10)
    }

    func testPaymentReleasesLimitAndCashFlowCountsItOnce() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let card = CreditCard(name: "Principal", limitCents: 200_000, closingDay: 25, dueDay: 5)
        context.insert(card)
        context.insert(Transaction(title: "Receita", amountCents: 500_000, kind: .income, date: date(2025, 1, 1)))
        try CreditCardViewModel().purchase(context: context, title: "Compra", amountCents: 120_000,
                                           date: date(2025, 1, 20), installments: 1, card: card, category: nil)
        let invoice = try XCTUnwrap(InvoiceEngine().invoices(for: card, through: date(2025, 12, 31)).first)
        try CreditCardViewModel().pay(context: context, card: card, invoice: invoice)
        XCTAssertThrowsError(try CreditCardViewModel().pay(context: context, card: card, invoice: invoice))
        XCTAssertEqual(card.availableLimitCents, 200_000)
        let invoices = InvoiceEngine().invoices(for: card, through: date(2025, 12, 31))
        XCTAssertEqual(invoices.first?.remainingCents, 0)
        let snapshot = DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
                                                     cards: [card], subscriptions: [], payments: card.payments,
                                                     month: .now)
        XCTAssertEqual(snapshot.balance, 380_000)
        XCTAssertEqual(snapshot.pendingInvoices, 0)
    }

    func testRenewalsCatchUpWithoutDoubleCharging() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let subscription = Subscription(title: "Internet", amountCents: 10_000, cycle: .monthly,
                                        nextRenewalDate: date(2025, 1, 31), category: nil, card: nil)
        context.insert(subscription)
        try RecurrenceEngine().synchronize(context: context, today: date(2025, 3, 31))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 3)
        XCTAssertEqual(subscription.nextRenewalDate, date(2025, 4, 30))
        try RecurrenceEngine().synchronize(context: context, today: date(2025, 3, 31))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 3)
        let dates = try context.fetch(FetchDescriptor<Transaction>()).map(\.date).sorted()
        XCTAssertEqual(dates, [date(2025, 1, 31), date(2025, 2, 28), date(2025, 3, 31)])
    }

    func testLeapYearAndWeeklyRecurrence() {
        let yearly = Subscription(title: "Anual", amountCents: 100, cycle: .yearly,
                                  nextRenewalDate: date(2024, 2, 29), category: nil, card: nil)
        XCTAssertEqual(RecurrenceEngine().date(for: yearly, index: 1), date(2025, 2, 28))
        XCTAssertEqual(RecurrenceEngine().date(for: yearly, index: 4), date(2028, 2, 29))
        let weekly = Subscription(title: "Semanal", amountCents: 100, cycle: .weekly,
                                  nextRenewalDate: date(2025, 1, 31), category: nil, card: nil)
        XCTAssertEqual(RecurrenceEngine().date(for: weekly, index: 1), date(2025, 2, 7))
    }

    func testProjectionDoesNotPersistFutureRenewals() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let card = CreditCard(name: "Principal", limitCents: 200_000, closingDay: 25, dueDay: 5)
        context.insert(card)
        let subscription = Subscription(title: "Streaming", amountCents: 3000, cycle: .monthly,
                                        nextRenewalDate: date(2025, 2, 26), category: nil, card: card)
        context.insert(subscription)
        try context.save()
        let invoices = InvoiceEngine().invoices(for: card, subscriptions: [subscription],
                                                through: date(2025, 4, 30), today: date(2025, 2, 1))
        XCTAssertEqual(invoices.first?.dueDate, date(2025, 4, 7))
        XCTAssertEqual(invoices.first?.totalCents, 3000)
        XCTAssertEqual(invoices.first?.payableCents, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(card.usedLimitCents, 0)
    }

    func testDeletingSubscriptionKeepsHistoricalCharges() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let subscription = Subscription(title: "Serviço", amountCents: 2000, cycle: .monthly,
                                        nextRenewalDate: date(2025, 1, 1), category: nil, card: nil)
        context.insert(subscription)
        try RecurrenceEngine().synchronize(context: context, today: date(2025, 1, 1))
        try SubscriptionViewModel().delete(subscription, context: context)
        let transaction = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertNil(transaction.subscription)
        XCTAssertEqual(transaction.amountCents, 2000)
        XCTAssertThrowsError(try TransactionViewModel().deleteCash(transaction, context: context))
    }

    func testPausingSubscriptionDoesNotCreateNewCharges() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let subscription = Subscription(title: "Serviço", amountCents: 2000, cycle: .monthly,
                                        nextRenewalDate: date(2025, 1, 1), category: nil, card: nil)
        subscription.isActive = false
        context.insert(subscription)
        try RecurrenceEngine().synchronize(context: context, today: date(2025, 12, 31))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
    }

    func testCashCRUD() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let vm = TransactionViewModel()
        try vm.saveCash(context: context, title: "Salário", amountText: "2.000,00", kind: .income,
                        date: date(2025, 1, 1), category: nil)
        let transaction = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        try vm.saveCash(context: context, transaction: transaction, title: "Salário atualizado", amountText: "2.100,00",
                        kind: .income, date: date(2025, 1, 1), category: nil)
        XCTAssertEqual(transaction.amountCents, 210_000)
        try vm.deleteCash(transaction, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
    }
}
