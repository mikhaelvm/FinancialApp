import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class CreditCardViewModel {
    static let deletionExplanation = "Exclui cartão, compras e faturas. Mantém pagamentos no Extrato e pausa recorrências vinculadas."
    func save(context: ModelContext, card: CreditCard? = nil, name: String,
              limitText: String, closingDay: Int, dueDay: Int) throws {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let limit = Money.parse(limitText),
              (1...31).contains(closingDay), (1...31).contains(dueDay) else {
            throw FinanceError.invalid("Preencha o nome, um limite positivo e dias entre 1 e 31.")
        }
        if let card {
            guard limit >= card.usedLimitCents else {
                throw FinanceError.invalid("O limite não pode ser menor que o valor já comprometido.")
            }
            card.name = title
            card.limitCents = limit
            card.closingDay = closingDay
            card.dueDay = dueDay
        } else {
            context.insert(CreditCard(name: title, limitCents: limit, closingDay: closingDay, dueDay: dueDay))
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func purchase(context: ModelContext, title: String, amountCents: Int64, date: Date,
                  installments: Int, card: CreditCard, category: Category?) throws {
        guard date <= Date.now else { throw FinanceError.invalid("Compras devem ter data de hoje ou anterior.") }
        guard amountCents <= card.availableLimitCents else {
            throw FinanceError.invalid("O valor total da compra ultrapassa o limite disponível.")
        }
        let amounts = try InvoiceEngine().installmentAmounts(totalCents: amountCents, count: installments)
        let purchaseID = UUID()
        for (index, amount) in amounts.enumerated() {
            let dates = InvoiceEngine().dates(for: date, closingDay: card.closingDay,
                                               dueDay: card.dueDay, installmentOffset: index)
            context.insert(Transaction(title: title, amountCents: amount, kind: .expense,
                                       date: date, category: category, card: card,
                                       installmentNumber: index + 1, totalInstallments: installments,
                                       purchaseID: purchaseID, invoiceDueDate: dates.due,
                                       invoiceClosingDate: dates.closing))
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func pay(context: ModelContext, card: CreditCard, invoice: Invoice, date: Date = .now) throws {
        guard card.modelContext === context else { throw FinanceError.invalid("Este cartão já foi removido.") }
        // Re-read current charges/payments so a stale UI snapshot cannot pay the same bill twice.
        guard let current = InvoiceEngine().invoices(for: card, through: invoice.dueDate)
            .first(where: { $0.dueDate == invoice.dueDate }),
              FinanceDate.day(.now) >= current.closingDate, current.payableCents > 0 else {
            throw FinanceError.invalid("Somente faturas fechadas com saldo lançado podem ser pagas.")
        }
        guard date.timeIntervalSince1970.isFinite, FinanceDate.day(date) <= FinanceDate.day(.now),
              FinanceDate.day(date) >= current.closingDate else {
            throw FinanceError.invalid("Escolha uma data entre o fechamento da fatura e hoje.")
        }
        context.insert(InvoicePayment(card: card, invoiceDueDate: current.dueDate,
                                      date: FinanceDate.day(date), amountCents: current.payableCents))
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func deletePayment(context: ModelContext, payment: InvoicePayment) throws {
        guard payment.modelContext === context else { throw FinanceError.invalid("Este pagamento já foi removido.") }
        context.delete(payment)
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func editPurchase(context: ModelContext, card: CreditCard, purchaseID: UUID, title: String,
                      amountCents: Int64, date: Date, installments: Int, category: Category?) throws {
        guard card.modelContext === context,
              let purchase = CardPurchaseService.groups(for: card).first(where: { $0.purchaseID == purchaseID }) else {
            throw FinanceError.invalid("Esta compra já foi removida.")
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, date.timeIntervalSince1970.isFinite, FinanceDate.day(date) <= FinanceDate.day(.now),
              !purchase.isRecurring || installments == 1 else {
            throw FinanceError.invalid("Informe título e data válidos. Cobranças recorrentes não podem ser parceladas.")
        }
        let proposedAmounts = try InvoiceEngine().installmentAmounts(totalCents: amountCents, count: installments)
        let recalculates = purchase.amountCents != amountCents || purchase.installments != installments
            || FinanceDate.day(purchase.date) != FinanceDate.day(date)
        let amounts = recalculates ? proposedAmounts : purchase.transactions.map(\.amountCents)
        let dates: [(closing: Date, due: Date)] = try amounts.indices.map { index in
            if !recalculates {
                guard index < purchase.transactions.count,
                      let closing = purchase.transactions[index].invoiceClosingDate,
                      let due = purchase.transactions[index].invoiceDueDate else {
                    throw FinanceError.invalid("Datas da compra incompletas.")
                }
                return (closing, due)
            }
            return InvoiceEngine().dates(for: date, closingDay: card.closingDay, dueDay: card.dueDay, installmentOffset: index)
        }
        if !recalculates {
            for row in purchase.transactions { row.title = title; row.category = category }
            do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
            return
        }
        let originalIDs = Set(purchase.transactions.map(\.id))
        var charges: [Date: Int64] = [:]
        for transaction in card.transactions where !originalIDs.contains(transaction.id) {
            guard let due = transaction.invoiceDueDate else { throw FinanceError.invalid("Há uma compra sem vencimento neste cartão.") }
            charges[due, default: 0] += transaction.amountCents
        }
        for index in amounts.indices { charges[dates[index].due, default: 0] += amounts[index] }
        let affected = Set(purchase.transactions.compactMap(\.invoiceDueDate)).union(dates.map { $0.due })
        let originalPayments = card.payments
        var releases: [(payment: InvoicePayment, amount: Int64)] = []
        for due in affected.sorted() {
            var excess = max(0, originalPayments.filter { $0.invoiceDueDate == due }.reduce(Int64(0)) { $0 + $1.amountCents } - (charges[due] ?? 0))
            for payment in originalPayments.filter({ $0.invoiceDueDate == due }).sorted(by: { $0.date > $1.date }) where excess > 0 {
                let portion = min(excess, payment.amountCents)
                releases.append((payment, portion)); excess -= portion
            }
        }
        var purchaseCharges: [Date: Int64] = [:]
        for index in amounts.indices { purchaseCharges[dates[index].due, default: 0] += amounts[index] }
        var transferNeeds: [Date: Int64] = [:]
        for (due, amount) in purchaseCharges {
            let paid = originalPayments.filter { $0.invoiceDueDate == due }.reduce(Int64(0)) { $0 + $1.amountCents }
            transferNeeds[due] = min(amount, max(0, (charges[due] ?? 0) - paid))
        }
        let released = releases.reduce(Int64(0)) { $0 + $1.amount }
        let unallocated = max(0, released - transferNeeds.values.reduce(Int64(0), +))
        let totalCharges = charges.values.reduce(Int64(0), +)
        let totalPaid = originalPayments.reduce(Int64(0)) { $0 + $1.amountCents }
        let projectedUsed = max(0, totalCharges - totalPaid + unallocated)
        guard projectedUsed <= max(card.limitCents, card.usedLimitCents) else {
            throw FinanceError.invalid("A alteração ultrapassa o limite disponível do cartão.")
        }
        // Move already-paid amounts with the corrected purchase, keeping their
        // actual payment date and cash effect. Only excess without a charge is cash.
        let operationID = UUID().uuidString
        for release in releases {
            let payment = release.payment
            let paymentDate = payment.date, paymentID = payment.id
            let entirePayment = release.amount == payment.amountCents
            var reused = false, remaining = release.amount
            if !entirePayment { payment.amountCents -= release.amount }
            for due in transferNeeds.keys.sorted() where remaining > 0 {
                let portion = min(remaining, transferNeeds[due] ?? 0)
                guard portion > 0 else { continue }
                if entirePayment && !reused {
                    payment.invoiceDueDate = due; payment.amountCents = portion; reused = true
                } else {
                    context.insert(InvoicePayment(card: card, invoiceDueDate: due, date: paymentDate, amountCents: portion))
                }
                transferNeeds[due, default: 0] -= portion; remaining -= portion
            }
            if entirePayment && !reused { context.delete(payment) }
            if remaining > 0 {
                context.insert(Transaction(title: "Pagamento de fatura • \(card.name)", amountCents: remaining, kind: .expense, date: paymentDate,
                    recurrenceKey: "preserved-card-payment:" + paymentID.uuidString + ":edit:" + operationID))
            }
        }
        for index in amounts.indices {
            let model = index < purchase.transactions.count ? purchase.transactions[index]
                : Transaction(title: title, amountCents: amounts[index], kind: .expense, date: FinanceDate.day(date), card: card, purchaseID: purchaseID)
            if model.modelContext == nil { context.insert(model) }
            model.title = title; model.category = category
            if recalculates {
                model.amountCents = amounts[index]; model.date = FinanceDate.day(date)
                model.installmentNumber = index + 1; model.totalInstallments = installments
                model.invoiceClosingDate = dates[index].closing; model.invoiceDueDate = dates[index].due
            }
        }
        for model in purchase.transactions.dropFirst(amounts.count) { context.delete(model) }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func deletePurchase(context: ModelContext, card: CreditCard, purchaseID: UUID) throws {
        guard card.modelContext === context else { throw FinanceError.invalid("O cartão já foi removido ou não pertence a este contexto.") }
        guard let purchase = CardPurchaseService.groups(for: card).first(where: { $0.purchaseID == purchaseID }) else {
            throw FinanceError.invalid("Esta compra já foi removida.")
        }
        let deletedIDs = Set(purchase.transactions.map(\.id))
        for due in Set(purchase.transactions.compactMap(\.invoiceDueDate)) {
            let remainingCharges = card.transactions.filter { $0.invoiceDueDate == due && !deletedIDs.contains($0.id) }
                .reduce(Int64(0)) { $0 + $1.amountCents }
            let payments = card.payments.filter { $0.invoiceDueDate == due }.sorted { $0.date > $1.date }
            var excess = max(0, payments.reduce(Int64(0)) { $0 + $1.amountCents } - remainingCharges)
            for payment in payments where excess > 0 {
                let portion = min(excess, payment.amountCents)
                context.insert(Transaction(title: "Pagamento de fatura • \(card.name)", amountCents: portion,
                    kind: .expense, date: payment.date,
                    recurrenceKey: "preserved-card-payment:" + payment.id.uuidString + ":purchase:" + purchaseID.uuidString))
                if portion == payment.amountCents { context.delete(payment) }
                else { payment.amountCents -= portion }
                excess -= portion
            }
        }
        for transaction in purchase.transactions { context.delete(transaction) }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func delete(context: ModelContext, card: CreditCard) throws {
        guard card.modelContext === context else { throw FinanceError.invalid("Este cartão já foi removido.") }
        // Keep realized cash outflows even after removing the card and its history.
        for payment in card.payments {
            context.insert(Transaction(title: "Pagamento de fatura • \(card.name)", amountCents: payment.amountCents,
                kind: .expense, date: payment.date, recurrenceKey: "preserved-card-payment:" + payment.id.uuidString))
        }
        for subscription in card.subscriptions { subscription.isActive = false; subscription.card = nil }
        context.delete(card)
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }
}
