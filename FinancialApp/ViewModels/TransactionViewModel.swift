import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class TransactionViewModel {
    func saveCash(context: ModelContext, transaction: Transaction? = nil, title: String,
                  amountText: String, kind: TransactionKind, date: Date, category: Category?) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let cents = Money.parse(amountText), date <= Date.now else {
            throw FinanceError.invalid("Informe título, valor positivo e data de hoje ou anterior.")
        }
        if let transaction {
            guard transaction.card == nil, transaction.subscription == nil, transaction.recurrenceKey == nil else {
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
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func deleteCash(_ transaction: Transaction, context: ModelContext) throws {
        guard transaction.card == nil, transaction.subscription == nil,
              transaction.recurrenceKey == nil else {
            throw FinanceError.invalid("Lançamentos automáticos são mantidos no histórico. Gerencie a assinatura para cobranças futuras.")
        }
        context.delete(transaction)
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
