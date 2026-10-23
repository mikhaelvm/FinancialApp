import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class TransactionViewModel {
    static let deletionExplanation = "Remove apenas este lançamento e recalcula o saldo. As próximas cobranças recorrentes permanecem ativas. Se for o registro de uma conta agendada paga, ela voltará a ficar pendente na Agenda."

    func saveCash(context: ModelContext, transaction: Transaction? = nil, title: String,
                  amountText: String, kind: TransactionKind, date: Date, category: Category?) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let cents = Money.parse(amountText), date <= Date.now else {
            throw FinanceError.invalid("Informe título, valor positivo e data de hoje ou anterior.")
        }
        if let transaction {
            try ensureNotScheduledPayment(transaction, context: context)
            guard transaction.card == nil, transaction.subscription == nil, !transaction.isAutomaticRecurrence else {
                throw FinanceError.invalid("Este lançamento é gerenciado pelo cartão ou pela assinatura.")
            }
            transaction.title = name
            transaction.amountCents = cents
            transaction.kindRaw = kind.rawValue
            transaction.date = date
            transaction.category = category
        } else {
            context.insert(Transaction(title: name, amountCents: cents, kind: kind, date: date, category: category))
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func deleteCash(_ transaction: Transaction, context: ModelContext) throws {
        guard transaction.modelContext === context, transaction.card == nil else {
            throw FinanceError.invalid("Exclua compras de cartão pelo detalhe da compra, para manter as parcelas e faturas consistentes.")
        }
        for payment in try context.fetch(FetchDescriptor<ScheduledPayment>()) where payment.paidTransactionID == transaction.id {
            payment.isPaid = false
            payment.paidTransactionID = nil
        }
        // Recurrence synchronization has already advanced past this occurrence.
        // Removing its receipt does not rewind the schedule or pause future renewals.
        context.delete(transaction)
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    private func ensureNotScheduledPayment(_ transaction: Transaction, context: ModelContext) throws {
        if try context.fetch(FetchDescriptor<ScheduledPayment>()).contains(where: { $0.paidTransactionID == transaction.id }) {
            throw FinanceError.invalid("Este lançamento é o comprovante de uma conta paga na Agenda e é mantido no histórico.")
        }
    }
}
