import Foundation

struct InvoiceLine: Identifiable {
    let id: String
    let title: String
    let amountCents: Int64
    let installmentNumber: Int
    let totalInstallments: Int
    let category: Category?
    let isProjected: Bool
}

struct Invoice: Identifiable {
    let dueDate: Date
    let closingDate: Date
    var lines: [InvoiceLine]
    var paidCents: Int64
    var id: Date { dueDate }
    var totalCents: Int64 { lines.reduce(0) { $0 + $1.amountCents } }
    var remainingCents: Int64 { max(0, totalCents - paidCents) }
    var recordedCents: Int64 { lines.filter { !$0.isProjected }.reduce(0) { $0 + $1.amountCents } }
    var payableCents: Int64 { max(0, recordedCents - paidCents) }
    func status(on today: Date = .now) -> String {
        if remainingCents == 0 { return "Paga" }
        if FinanceDate.day(today) > dueDate { return "Vencida" }
        return FinanceDate.day(today) >= closingDate ? "Fechada" : "Aberta / futura"
    }
}

struct InvoiceEngine {
    /// Purchases on closing day start a new billing cycle.
    func dates(for purchaseDate: Date, closingDay: Int, dueDay: Int,
               installmentOffset: Int = 0) -> (closing: Date, due: Date) {
        let purchase = FinanceDate.day(purchaseDate)
        // A closing shifted into the next month still belongs to its original cycle.
        var baseMonth = FinanceDate.monthOffset(-1, from: purchase)
        while purchase >= FinanceDate.nextWeekday(FinanceDate.date(day: closingDay, inMonth: baseMonth)) {
            baseMonth = FinanceDate.monthOffset(1, from: baseMonth)
        }
        let closingMonth = FinanceDate.monthOffset(installmentOffset, from: baseMonth)
        let closing = FinanceDate.nextWeekday(FinanceDate.date(day: closingDay, inMonth: closingMonth))
        let dueMonth = FinanceDate.monthOffset(dueDay > closingDay ? 0 : 1, from: closingMonth)
        let due = FinanceDate.nextWeekday(FinanceDate.date(day: dueDay, inMonth: dueMonth))
        return (closing, max(closing, due))
    }

    func installmentAmounts(totalCents: Int64, count: Int) throws -> [Int64] {
        guard totalCents > 0, totalCents <= Money.maximumCents,
              (1...120).contains(count), totalCents >= Int64(count) else {
            throw FinanceError.invalid("Informe um valor válido e de 1 a 120 parcelas, de pelo menos R$ 0,01.")
        }
        let base = totalCents / Int64(count)
        let remainder = totalCents % Int64(count)
        return (0..<count).map { base + (Int64($0) < remainder ? 1 : 0) }
    }

    func invoices(for card: CreditCard, subscriptions: [Subscription] = [],
                  through horizon: Date, today: Date = .now) -> [Invoice] {
        var grouped: [Date: Invoice] = [:]
        func append(_ line: InvoiceLine, closing: Date, due: Date) {
            guard due < FinanceDate.monthOffset(1, from: horizon) else { return }
            var invoice = grouped[due] ?? Invoice(dueDate: due, closingDate: closing,
                                                 lines: [], paidCents: 0)
            invoice.lines.append(line)
            grouped[due] = invoice
        }
        for transaction in card.transactions {
            guard let due = transaction.invoiceDueDate, let closing = transaction.invoiceClosingDate else { continue }
            append(InvoiceLine(id: transaction.id.uuidString, title: transaction.title,
                               amountCents: transaction.amountCents,
                               installmentNumber: transaction.installmentNumber,
                               totalInstallments: transaction.totalInstallments,
                               category: transaction.category, isProjected: false), closing: closing, due: due)
        }
        for subscription in subscriptions where subscription.isActive && subscription.card?.id == card.id {
            for occurrence in RecurrenceEngine().occurrences(of: subscription, through: horizon) {
                // Due occurrences are persisted by synchronization; virtual lines only represent the future.
                guard occurrence.date > FinanceDate.day(today) else { continue }
                let dates = dates(for: occurrence.date, closingDay: card.closingDay, dueDay: card.dueDay)
                append(InvoiceLine(id: occurrence.key, title: subscription.title,
                                   amountCents: subscription.amountCents, installmentNumber: 1,
                                   totalInstallments: 1, category: subscription.category, isProjected: true),
                       closing: dates.closing, due: dates.due)
            }
        }
        for payment in card.payments {
            if var invoice = grouped[payment.invoiceDueDate] {
                invoice.paidCents += payment.amountCents
                grouped[payment.invoiceDueDate] = invoice
            }
        }
        return grouped.values.sorted { $0.dueDate < $1.dueDate }
    }
}
