import XCTest
import SwiftData
@testable import FinancialApp
@testable import class FinancialApp.Category

@MainActor
final class LedgerPlanningTests: XCTestCase {
    private func date(_ day: Int, hour: Int = 0) -> Date {
        FinanceDate.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func item(id: String = "bill", due: Date) -> PaymentCommitment {
        PaymentCommitment(id: id, title: "Conta", amountCents: 12_000, dueDate: due,
                          kind: .scheduled, sourceID: UUID(), detail: "")
    }

    func testAgendaKeepsOnlyNextInvoicePerCardAndAllOverdueInvoices() {
        let first = UUID(), second = UUID()
        func invoice(_ id: String, _ card: UUID, _ day: Int) -> PaymentCommitment {
            PaymentCommitment(id: id, title: "Fatura", amountCents: 1000, dueDate: date(day),
                              kind: .invoice, sourceID: card, detail: "")
        }
        let rows = [invoice("later", first, 30), invoice("next", first, 25),
                    invoice("late1", first, 10), invoice("late2", first, 15),
                    invoice("other", second, 26), item(id: "scheduled", due: date(30))]
        let result = PaymentPlanner.agendaItems(rows, today: date(22))
        XCTAssertEqual(result.map(\.id), ["late1", "late2", "next", "other", "scheduled"])
        let paidNext = rows.filter { $0.id != "next" }
        XCTAssertTrue(PaymentPlanner.agendaItems(paidNext, today: date(22)).contains { $0.id == "later" })
    }

    func testReminderIncludesAdvanceAndDueDayAtChosenHour() {
        let preferences = ReminderPreferences(enabled: true, daysBefore: 3, hour: 10, minute: 30)
        let reminders = ReminderPlanner().reminders(for: [item(due: date(25))], preferences: preferences, now: date(21))
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.daysBefore), [3, 0])
        XCTAssertEqual(FinanceDate.calendar.component(.day, from: reminders[0].fireDate), 22)
        XCTAssertTrue(reminders.allSatisfy { FinanceDate.calendar.component(.hour, from: $0.fireDate) == 10 })
        XCTAssertTrue(reminders.allSatisfy { FinanceDate.calendar.component(.minute, from: $0.fireDate) == 30 })
    }

    func testSameDayOnlyDoesNotDuplicateOrSchedulePastAlerts() {
        let prefs = ReminderPreferences(enabled: true, daysBefore: 0)
        let bill = item(due: date(25))
        XCTAssertEqual(ReminderPlanner().reminders(for: [bill, bill], preferences: prefs, now: date(24)).count, 1)
        XCTAssertTrue(ReminderPlanner().reminders(for: [bill], preferences: prefs, now: date(25, hour: 12)).isEmpty)
        XCTAssertTrue(ReminderPlanner().reminders(for: [bill], preferences: ReminderPreferences(), now: date(24)).isEmpty)
    }

    func testQueueKeepsNearestSixtyAlertsWithStableIdentifiers() {
        let bills = (0..<100).map { offset in
            item(id: "bill-\(offset)", due: FinanceDate.calendar.date(byAdding: .day, value: offset + 1, to: date(1))!)
        }
        let prefs = ReminderPreferences(enabled: true, daysBefore: 0)
        let first = ReminderPlanner().reminders(for: bills, preferences: prefs, now: date(1))
        let reversed = ReminderPlanner().reminders(for: Array(bills.reversed()), preferences: prefs, now: date(1))
        XCTAssertEqual(first.count, 60)
        XCTAssertEqual(first.map(\.id), reversed.map(\.id))
        XCTAssertEqual(first.first?.commitment.id, "bill-0")
        XCTAssertEqual(first.last?.commitment.id, "bill-59")
    }

    func testScheduledPaymentChangesOnlyProjectionUntilPaidAndCannotBePaidTwice() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let vm = ScheduledPaymentViewModel()
        try vm.save(context: context, title: "Energia", amountText: "120,00", dueDate: .now, notes: "", categoryID: nil)
        let bill = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledPayment>()).first)
        let before = DashboardViewModel().snapshot(transactions: [], cards: [], subscriptions: [], payments: [], month: .now, scheduled: [bill])
        XCTAssertEqual(before.balance, 0)
        XCTAssertEqual(before.projectedBalance, -12_000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        try vm.pay(bill, context: context)
        XCTAssertThrowsError(try vm.pay(bill, context: context))
        XCTAssertTrue(bill.isPaid)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(bill.paidTransactionID, transactions.first?.id)
        let after = DashboardViewModel().snapshot(transactions: transactions, cards: [], subscriptions: [], payments: [], month: .now, scheduled: [bill])
        XCTAssertEqual(after.balance, -12_000)
        XCTAssertEqual(after.projectedBalance, -12_000)
        XCTAssertTrue(PaymentPlanner().commitments(cards: [], subscriptions: [], scheduled: [bill], through: .distantFuture).isEmpty)
    }

    func testCardRenewalAndInvoiceDoNotDoubleCountProjectedCash() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let card = CreditCard(name: "Principal", limitCents: 100_000, closingDay: 20, dueDay: 25)
        context.insert(card)
        let subscription = Subscription(title: "Streaming", amountCents: 3000, cycle: .monthly,
                                        nextRenewalDate: date(10), category: nil, card: card)
        context.insert(subscription)
        try context.save()
        let commitments = PaymentPlanner().commitments(cards: [card], subscriptions: [subscription], scheduled: [],
                                                        through: date(31), today: date(1))
        XCTAssertEqual(commitments.count, 2)
        XCTAssertEqual(commitments.filter { $0.affectsCashFlow }.reduce(Int64(0)) { $0 + $1.amountCents }, 3000)
        XCTAssertEqual(commitments.filter { $0.kind == .subscription }.first?.affectsCashFlow, false)
    }

    func testPausedAndDeletedBillsProduceNoFutureReminders() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let subscription = Subscription(title: "Serviço", amountCents: 3000, cycle: .monthly,
                                        nextRenewalDate: date(10), category: nil, card: nil)
        subscription.isActive = false
        context.insert(subscription)
        let bill = ScheduledPayment(title: "Conta", amountCents: 100, dueDate: date(25))
        context.insert(bill)
        try context.save()
        try ScheduledPaymentViewModel().delete(bill, context: context)
        let commitments = PaymentPlanner().commitments(cards: [], subscriptions: [subscription],
                                                        scheduled: try context.fetch(FetchDescriptor<ScheduledPayment>()),
                                                        through: date(31), today: date(1))
        XCTAssertTrue(commitments.isEmpty)
    }

    func testShortcutValueValidation() throws {
        XCTAssertEqual(try LedgerIntentSupport.cents(from: 12.34), 1234)
        XCTAssertEqual(try LedgerIntentSupport.cents(from: 0.01), 1)
        XCTAssertThrowsError(try LedgerIntentSupport.cents(from: .nan))
        XCTAssertThrowsError(try LedgerIntentSupport.cents(from: .infinity))
        XCTAssertThrowsError(try LedgerIntentSupport.cents(from: -1))
        XCTAssertThrowsError(try LedgerIntentSupport.cents(from: 0.001))
    }
}
