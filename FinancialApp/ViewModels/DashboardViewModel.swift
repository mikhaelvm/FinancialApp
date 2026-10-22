import Foundation
import Observation

struct CategoryExpense: Identifiable {
    let id: String
    let name: String
    let colorName: String
    var cents: Int64
}

struct MonthForecast: Identifiable {
    let month: Date
    let invoiceCents: Int64
    var id: Date { month }
}

struct DashboardSnapshot {
    let balance: Int64
    let income: Int64
    let cashExpenses: Int64
    let payments: Int64
    let pendingInvoices: Int64
    let upcomingCash: Int64
    let scheduledCents: Int64
    let categories: [CategoryExpense]
    let forecasts: [MonthForecast]
    var projectedBalance: Int64 { balance - pendingInvoices - upcomingCash - scheduledCents }
}

@MainActor @Observable
final class DashboardViewModel {
    func snapshot(transactions: [Transaction], cards: [CreditCard],
                  subscriptions: [Subscription], payments: [InvoicePayment],
                  month: Date, today: Date = .now, scheduled: [ScheduledPayment] = []) -> DashboardSnapshot {
        let endOfToday = FinanceDate.calendar.date(byAdding: .day, value: 1, to: FinanceDate.day(today))!
        let cash = transactions.filter { $0.card == nil && $0.date < endOfToday }
        let realizedPayments = payments.filter { $0.date < endOfToday }
        let balance = cash.reduce(Int64(0)) { $0 + ($1.kind == .income ? $1.amountCents : -$1.amountCents) }
            - realizedPayments.reduce(0) { $0 + $1.amountCents }
        let current = cash.filter { FinanceDate.sameMonth($0.date, month) }
        let income = current.filter { $0.kind == .income }.reduce(Int64(0)) { $0 + $1.amountCents }
        let expenses = current.filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let paid = realizedPayments.filter { FinanceDate.sameMonth($0.date, month) }.reduce(Int64(0)) { $0 + $1.amountCents }
        let horizon = FinanceDate.date(day: 31, inMonth: FinanceDate.monthOffset(11, from: month))
        let invoices = cards.flatMap { InvoiceEngine().invoices(for: $0, subscriptions: subscriptions, through: horizon, today: today) }
        // Include overdue invoices in the amount needed to get through this month.
        let nextMonth = FinanceDate.monthOffset(1, from: month)
        let pending = invoices.filter { $0.dueDate < nextMonth }.reduce(Int64(0)) { $0 + $1.remainingCents }
        let monthEnd = FinanceDate.calendar.date(byAdding: .day, value: -1, to: nextMonth)!
        let upcomingCash = subscriptions.filter { $0.isActive && $0.card == nil }.reduce(Int64(0)) { sum, subscription in
            sum + RecurrenceEngine().occurrences(of: subscription, through: monthEnd)
                .filter { $0.date > FinanceDate.day(today) }.reduce(0) { subtotal, _ in subtotal + subscription.amountCents }
        }
        var categories: [String: CategoryExpense] = [:]
        func add(category: Category?, cents: Int64) {
            let key = category?.id.uuidString ?? "other"
            var row = categories[key] ?? CategoryExpense(id: key, name: category?.name ?? "Sem categoria",
                                                         colorName: category?.colorName ?? "teal", cents: 0)
            row.cents += cents
            categories[key] = row
        }
        for transaction in current where transaction.kind == .expense {
            add(category: transaction.category, cents: transaction.amountCents)
        }
        for invoice in invoices where FinanceDate.sameMonth(invoice.dueDate, month) {
            for line in invoice.lines { add(category: line.category, cents: line.amountCents) }
        }
        let forecasts = (0..<12).map { offset in
            let date = FinanceDate.monthOffset(offset, from: month)
            return MonthForecast(month: date, invoiceCents: invoices.filter {
                FinanceDate.sameMonth($0.dueDate, date)
            }.reduce(Int64(0)) { $0 + $1.remainingCents })
        }
        let scheduledCents = scheduled.filter { !$0.isPaid && $0.dueDate < nextMonth }
            .reduce(Int64(0)) { $0 + $1.amountCents }
        return DashboardSnapshot(balance: balance, income: income, cashExpenses: expenses,
                                 payments: paid, pendingInvoices: pending, upcomingCash: upcomingCash, scheduledCents: scheduledCents,
                                 categories: categories.values.sorted { $0.cents > $1.cents }, forecasts: forecasts)
    }
}
