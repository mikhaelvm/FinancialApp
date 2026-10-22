import Foundation

enum PaymentKind: String {
    case invoice, subscription, scheduled
    var title: String {
        switch self {
        case .invoice: return "Fatura"
        case .subscription: return "Recorrência"
        case .scheduled: return "Conta a pagar"
        }
    }
    var symbol: String {
        switch self {
        case .invoice: return "creditcard.fill"
        case .subscription: return "repeat"
        case .scheduled: return "calendar.badge.clock"
        }
    }
}

struct PaymentCommitment: Identifiable {
    let id: String
    let title: String
    let amountCents: Int64
    let dueDate: Date
    let kind: PaymentKind
    let sourceID: UUID
    let detail: String
    var isProjected: Bool = false
    var affectsCashFlow: Bool = true
    func isOverdue(on date: Date = .now) -> Bool { dueDate < FinanceDate.day(date) }
}

struct PaymentPlanner {
    /// Agenda hides later invoices while retaining every overdue bill.
    /// Full projections remain available to notifications, widgets and cash-flow calculations.
    static func agendaItems(_ commitments: [PaymentCommitment], today: Date = .now) -> [PaymentCommitment] {
        var nextCards = Set<UUID>()
        return commitments.sorted {
            $0.dueDate == $1.dueDate ? $0.id < $1.id : $0.dueDate < $1.dueDate
        }.filter { item in
            guard item.kind == .invoice, !item.isOverdue(on: today) else { return true }
            return nextCards.insert(item.sourceID).inserted
        }
    }

    func commitments(cards: [CreditCard], subscriptions: [Subscription],
                     scheduled: [ScheduledPayment], through horizon: Date,
                     today: Date = .now, includeDismissed: Bool = false) -> [PaymentCommitment] {
        var result: [PaymentCommitment] = []
        for card in cards {
            for invoice in InvoiceEngine().invoices(for: card, subscriptions: subscriptions, through: horizon, today: today)
                where invoice.dueDate <= horizon && invoice.remainingCents > 0 {
                let key = FinanceDate.month(invoice.dueDate).timeIntervalSince1970
                result.append(PaymentCommitment(id: "invoice:\(card.id):\(key)", title: "Fatura \(card.name)",
                                                 amountCents: invoice.remainingCents, dueDate: invoice.dueDate,
                                                 kind: .invoice, sourceID: card.id,
                                                 detail: invoice.status(on: today),
                                                 isProjected: invoice.lines.contains { $0.isProjected }))
            }
        }
        for subscription in subscriptions where subscription.isActive {
            let method = subscription.card?.name ?? "Débito / conta"
            for occurrence in RecurrenceEngine().occurrences(of: subscription, through: horizon) {
                result.append(PaymentCommitment(id: "subscription:\(occurrence.key)", title: subscription.title,
                                                 amountCents: subscription.amountCents, dueDate: occurrence.date,
                                                 kind: .subscription, sourceID: subscription.id,
                                                 detail: method, isProjected: true,
                                                 affectsCashFlow: subscription.card == nil))
            }
            // Synchronization advances the renewal at midnight; today's charge still gets a reminder.
            for transaction in subscription.transactions where FinanceDate.day(transaction.date) == FinanceDate.day(today) {
                guard let key = transaction.recurrenceKey else { continue }
                result.append(PaymentCommitment(id: "subscription:\(key)", title: transaction.title,
                                                 amountCents: transaction.amountCents, dueDate: FinanceDate.day(transaction.date),
                                                 kind: .subscription, sourceID: subscription.id, detail: method,
                                                 affectsCashFlow: false))
            }
        }
        for payment in scheduled where !payment.isPaid && payment.dueDate <= horizon {
            result.append(PaymentCommitment(id: "scheduled:\(payment.id)", title: payment.title,
                                             amountCents: payment.amountCents, dueDate: payment.dueDate,
                                             kind: .scheduled, sourceID: payment.id, detail: payment.notes))
        }
        // Invoice and card renewal are separate events: renewal charges the card; invoice debits the account.
        var seen = Set<String>()
        let dismissed = includeDismissed ? Set<String>() : PaymentDismissalStore.ids()
        return result.filter { !dismissed.contains($0.id) && seen.insert($0.id).inserted }.sorted {
            $0.dueDate == $1.dueDate ? $0.id < $1.id : $0.dueDate < $1.dueDate
        }
    }
}
