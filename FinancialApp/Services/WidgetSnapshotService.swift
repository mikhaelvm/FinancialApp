import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func refresh(context: ModelContext) {
        guard LedgerWidgetStore.isAvailable else { return }
        do {
            if AppLockService.protectionEnabled {
                try LedgerWidgetStore.write(LedgerWidgetSnapshot(updatedAt: .now, month: FinanceDate.month(.now),
                    balance: 0, income: 0, expenses: 0, pendingInvoices: 0, projectedBalance: 0, upcoming: [],
                    hidesAmounts: true, budget: 0, budgetSpent: 0, accessProtected: true))
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
            let transactions = try context.fetch(FetchDescriptor<Transaction>())
            let cards = try context.fetch(FetchDescriptor<CreditCard>())
            let subscriptions = try context.fetch(FetchDescriptor<Subscription>())
            let payments = try context.fetch(FetchDescriptor<InvoicePayment>())
            let scheduled = try context.fetch(FetchDescriptor<ScheduledPayment>())
            let month = FinanceDate.month(.now)
            let snapshot = DashboardViewModel().snapshot(transactions: transactions, cards: cards, subscriptions: subscriptions,
                                                         payments: payments, month: month, scheduled: scheduled)
            let horizon = FinanceDate.calendar.date(byAdding: .day, value: 60, to: FinanceDate.day(.now))!
            let upcoming = PaymentPlanner().commitments(cards: cards, subscriptions: subscriptions, scheduled: scheduled, through: horizon)
                .filter(\.affectsCashFlow).sorted { $0.dueDate < $1.dueDate }.prefix(3)
                .map { LedgerWidgetPayment(id: $0.id, title: $0.title, date: $0.dueDate, cents: $0.amountCents) }
            try LedgerWidgetStore.write(LedgerWidgetSnapshot(updatedAt: .now, month: month, balance: snapshot.balance,
                                                            income: snapshot.income, expenses: snapshot.cashExpenses + snapshot.payments,
                                                            pendingInvoices: snapshot.pendingInvoices, projectedBalance: snapshot.projectedBalance,
                                                            upcoming: upcoming, hidesAmounts: LedgerPreferences.hidesAmounts,
                                                            budget: LedgerPreferences.monthlyBudgetCents,
                                                            budgetSpent: snapshot.categories.reduce(0) { $0 + $1.cents }))
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Never keep older visible amounts after privacy changes or a failed refresh.
            try? LedgerWidgetStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
