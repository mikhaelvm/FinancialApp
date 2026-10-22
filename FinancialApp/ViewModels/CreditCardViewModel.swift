import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class CreditCardViewModel {
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
        do { try context.save() } catch { context.rollback(); throw error }
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
        do { try context.save() } catch { context.rollback(); throw error }
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
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func delete(context: ModelContext, card: CreditCard) throws {
        guard card.transactions.isEmpty, card.payments.isEmpty, card.subscriptions.isEmpty else {
            throw FinanceError.invalid("Cartões com lançamentos ou assinaturas devem ser mantidos para preservar o histórico.")
        }
        context.delete(card)
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
