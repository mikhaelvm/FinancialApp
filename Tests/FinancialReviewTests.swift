import XCTest
import SwiftData
@testable import Trackr
@testable import class Trackr.Category

@MainActor
final class FinancialReviewTests: XCTestCase {
    private func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        FinanceDate.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testSixMonthCashFlowCountsPaymentsOnceAndExcludesFutureCash() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let card = CreditCard(name: "Principal", limitCents: 100000, closingDay: 20, dueDay: 25)
        context.insert(card)
        let transactions = [
            Transaction(title: "Receita", amountCents: 100000, kind: .income, date: date(10, 1)),
            Transaction(title: "Conta", amountCents: 10000, kind: .expense, date: date(10, 2)),
            Transaction(title: "Compra no cartão", amountCents: 20000, kind: .expense, date: date(10, 3)),
            Transaction(title: "Entrada futura", amountCents: 99999, kind: .income, date: date(10, 23))
        ]
        for transaction in transactions { context.insert(transaction) }
        transactions[2].card = card
        let payment = InvoicePayment(card: card, invoiceDueDate: date(10, 25), date: date(10, 20), amountCents: 20000)
        context.insert(payment); try context.save()
        let rows = FinancialReview.months(transactions: transactions, payments: [payment], today: date(10, 22))
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.first?.month, date(5, 1))
        XCTAssertEqual(rows.last?.income, 100000)
        XCTAssertEqual(rows.last?.expenses, 30000)
        XCTAssertEqual(rows.last?.net, 70000)
    }

    func testComparisonUsesMatchingDaysAndHandlesAbsentHistory() {
        let transactions = [
            Transaction(title: "Antes", amountCents: 10000, kind: .expense, date: date(9, 2)),
            Transaction(title: "Depois do corte", amountCents: 99999, kind: .expense, date: date(9, 30)),
            Transaction(title: "Atual", amountCents: 15000, kind: .expense, date: date(10, 2))
        ]
        let comparison = FinancialReview.comparison(transactions: transactions, payments: [], today: date(10, 22))
        XCTAssertEqual(comparison.current, 15000); XCTAssertEqual(comparison.previous, 10000)
        XCTAssertEqual(comparison.percentChange, 50)
        XCTAssertNil(FinancialReview.comparison(transactions: [], payments: [], today: date(10, 22)).percentChange)
    }

    func testPeriodsCoverYearBoundariesAndExactlyThirtyCalendarDays() {
        let today = date(1, 15)
        XCTAssertTrue(TrackrTransactionPeriod.previousMonth.includes(date(12, 31, year: 2025), today: today))
        XCTAssertFalse(TrackrTransactionPeriod.previousMonth.includes(date(1, 1), today: today))
        XCTAssertTrue(TrackrTransactionPeriod.thirtyDays.includes(date(12, 17, year: 2025), today: today))
        XCTAssertFalse(TrackrTransactionPeriod.thirtyDays.includes(date(12, 16, year: 2025), today: today))
        XCTAssertFalse(TrackrTransactionPeriod.thirtyDays.includes(date(1, 16), today: today))
    }

    func testDraftCreatesFreshCashWithoutCarryingImportedIdentityOrRecurrence() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let original = Transaction(title: "Mercado", amountCents: 5000, kind: .expense, date: date(9, 10), recurrenceKey: "statement:old")
        context.insert(original); try context.save()
        let draft = TrackrTransactionDraft(transaction: original)
        try TransactionViewModel().saveCash(context: context, title: draft.title, amountText: Money.input(draft.amountCents), kind: draft.kind, date: date(10, 22), category: nil)
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(rows.count, 2)
        let copy = try XCTUnwrap(rows.first { $0.id != original.id })
        XCTAssertNil(copy.recurrenceKey); XCTAssertNil(copy.card); XCTAssertNil(copy.subscription)
        XCTAssertEqual(copy.date, date(10, 22)); XCTAssertEqual(original.date, date(9, 10))
    }
}
