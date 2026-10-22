import XCTest
import SwiftData
@testable import FinancialApp
@testable import class FinancialApp.Category

@MainActor
final class CardOperationsAndMoneyTests: XCTestCase {
    private func date(_ month: Int, _ day: Int) -> Date {
        FinanceDate.calendar.date(from: DateComponents(year: 2025, month: month, day: day))!
    }
    private func card(context: ModelContext) throws -> CreditCard {
        let card = CreditCard(name: "Principal", limitCents: 100000, closingDay: 20, dueDay: 25)
        context.insert(card); try context.save()
        return card
    }
    private func balance(context: ModelContext) throws -> Int64 {
        DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
            cards: try context.fetch(FetchDescriptor<CreditCard>()), subscriptions: [],
            payments: try context.fetch(FetchDescriptor<InvoicePayment>()), month: .now).balance
    }

    func testBankStyleDigitsFormattingDeletionAndPasting() {
        XCTAssertEqual(Money.bankInput("1"), "0,01")
        XCTAssertEqual(Money.bankInput("123456"), "1.234,56")
        XCTAssertEqual(Money.bankInput("1.234,56"), "1.234,56")
        XCTAssertEqual(Money.bankInput("R$ 1.234,56"), "1.234,56")
        XCTAssertEqual(Money.bankInput("1,0"), "0,10")
        XCTAssertEqual(Money.bankInput("0,0"), "")
        XCTAssertEqual(Money.bankInput(""), "")
        XCTAssertEqual(Money.parse(Money.bankInput("123456")), 123456)
    }

    func testBankStyleRejectsOverflowWithoutLosingPreviousValue() {
        XCTAssertEqual(Money.bankInput("1000000000001", previous: "1,00"), "1,00")
        XCTAssertEqual(Money.bankInput(String(repeating: "9", count: 30), previous: "12,34"), "12,34")
        XCTAssertEqual(Money.parse(Money.bankInput("1000000000000")), Money.maximumCents)
    }

    func testPurchaseDeletionRemovesTheEntireInstallmentGroupAndReleasesLimit() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try card(context: context)
        let model = CreditCardViewModel()
        try model.purchase(context: context, title: "Relógio", amountCents: 12000, date: date(1, 1), installments: 12, card: card, category: nil)
        try model.purchase(context: context, title: "Outra compra", amountCents: 5000, date: date(1, 2), installments: 1, card: card, category: nil)
        let group = try XCTUnwrap(CardPurchaseService.groups(for: card).first { $0.title == "Relógio" })
        XCTAssertEqual(group.transactions.count, 12); XCTAssertEqual(group.amountCents, 12000)
        try model.deletePurchase(context: context, card: card, purchaseID: group.purchaseID)
        XCTAssertEqual(card.transactions.count, 1)
        XCTAssertEqual(card.usedLimitCents, 5000)
        XCTAssertEqual(card.availableLimitCents, 95000)
        XCTAssertEqual(try balance(context: context), 0)
    }

    func testPaidPurchaseDeletionPreservesCashAndDoesNotFreeAnotherPurchasesLimit() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try card(context: context)
        let model = CreditCardViewModel()
        try model.purchase(context: context, title: "Paga", amountCents: 10000, date: date(1, 1), installments: 1, card: card, category: nil)
        try model.purchase(context: context, title: "Futura", amountCents: 5000, date: date(2, 1), installments: 1, card: card, category: nil)
        let group = try XCTUnwrap(CardPurchaseService.groups(for: card).first { $0.title == "Paga" })
        let due = try XCTUnwrap(group.transactions.first?.invoiceDueDate)
        context.insert(InvoicePayment(card: card, invoiceDueDate: due, date: date(1, 25), amountCents: 10000))
        try context.save()
        let before = try balance(context: context)
        try model.deletePurchase(context: context, card: card, purchaseID: group.purchaseID)
        XCTAssertEqual(try balance(context: context), before)
        XCTAssertEqual(before, -10000)
        XCTAssertEqual(card.usedLimitCents, 5000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InvoicePayment>()), 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Transaction>()).contains { $0.card == nil && $0.amountCents == 10000 })
    }

    func testPartialPaymentKeepsItsAllocationAndOnlyMovesExcessToCash() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try card(context: context)
        let model = CreditCardViewModel()
        try model.purchase(context: context, title: "Excluir", amountCents: 20000, date: date(1, 1), installments: 1, card: card, category: nil)
        try model.purchase(context: context, title: "Manter", amountCents: 10000, date: date(1, 2), installments: 1, card: card, category: nil)
        let group = try XCTUnwrap(CardPurchaseService.groups(for: card).first { $0.title == "Excluir" })
        let due = try XCTUnwrap(group.transactions.first?.invoiceDueDate)
        context.insert(InvoicePayment(card: card, invoiceDueDate: due, date: date(1, 25), amountCents: 15000))
        try context.save()
        try model.deletePurchase(context: context, card: card, purchaseID: group.purchaseID)
        XCTAssertEqual(try balance(context: context), -15000)
        XCTAssertEqual(card.payments.reduce(0) { $0 + $1.amountCents }, 10000)
        let cash = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.card == nil }
        XCTAssertEqual(cash.reduce(0) { $0 + $1.amountCents }, 5000)
        let imported = StatementRow(id: "statement:bank-payment", date: date(1, 25), title: "PAGAMENTO CARTAO", signedCents: -15000)
        XCTAssertTrue(try StatementImportService.prepare([imported], context: context)[0].isDuplicate)
    }

    func testDeletingCardPreservesPaymentsPausesRecurrencesAndClearsCharges() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext, card = try card(context: context)
        let model = CreditCardViewModel()
        try model.purchase(context: context, title: "Compra", amountCents: 12000, date: date(1, 1), installments: 3, card: card, category: nil)
        let due = try XCTUnwrap(card.transactions.first?.invoiceDueDate)
        context.insert(InvoicePayment(card: card, invoiceDueDate: due, date: date(1, 25), amountCents: 4000))
        let subscription = Subscription(title: "Streaming", amountCents: 1000, cycle: .monthly, nextRenewalDate: date(2, 1), category: nil, card: card)
        context.insert(subscription); try context.save()
        let before = try balance(context: context)
        try model.delete(context: context, card: card)
        XCTAssertEqual(try balance(context: context), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CreditCard>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InvoicePayment>()), 0)
        XCTAssertFalse(subscription.isActive); XCTAssertNil(subscription.card)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).filter { $0.card == nil }.count, 1)
        XCTAssertThrowsError(try model.delete(context: context, card: card))
    }

    func testLegacyDeepLinksOpenTheCorrectUnifiedPaymentsSection() {
        let router = LedgerRouter()
        router.open(URL(string: "ledger://subscriptions")!)
        XCTAssertEqual(router.selectedTab, .agenda); XCTAssertEqual(router.paymentsSection, .recurring)
        router.open(URL(string: "ledger://agenda")!)
        XCTAssertEqual(router.selectedTab, .agenda); XCTAssertEqual(router.paymentsSection, .calendar)
        router.openReminder(kind: "subscription")
        XCTAssertEqual(router.paymentsSection, .recurring)
    }
}
