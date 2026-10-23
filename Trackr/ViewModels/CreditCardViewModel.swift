import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class CreditCardViewModel {
    static let deletionExplanation = "O cartão, suas compras, parcelas e faturas serão removidos. Pagamentos já realizados serão preservados como despesas no Extrato, mantendo o saldo da conta. Recorrências vinculadas serão pausadas."
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

    func pay(context: ModelContext, card: CreditCard, invoice: Invoice) throws {
        // Re-read current charges/payments so a stale UI snapshot cannot pay the same bill twice.
        guard let current = InvoiceEngine().invoices(for: card, through: invoice.dueDate)
            .first(where: { $0.dueDate == invoice.dueDate }),
              FinanceDate.day(.now) >= current.closingDate, current.payableCents > 0 else {
            throw FinanceError.invalid("Somente faturas fechadas com saldo lançado podem ser pagas.")
        }
        context.insert(InvoicePayment(card: card, invoiceDueDate: current.dueDate,
                                      date: .now, amountCents: current.payableCents))
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
