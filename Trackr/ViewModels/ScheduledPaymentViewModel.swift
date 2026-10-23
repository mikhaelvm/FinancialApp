import Foundation
import SwiftData

@MainActor
final class ScheduledPaymentViewModel {
    func save(context: ModelContext, payment: ScheduledPayment? = nil, title: String,
              amountText: String, dueDate: Date, notes: String, categoryID: UUID?) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let cents = Money.parse(amountText) else {
            throw FinanceError.invalid("Informe o nome da conta e um valor válido, como 120,00.")
        }
        guard payment?.isPaid != true else { throw FinanceError.invalid("Este pagamento já foi concluído.") }
        if let payment {
            payment.title = name
            payment.amountCents = cents
            payment.dueDate = FinanceDate.day(dueDate)
            payment.notes = notes
            payment.categoryID = categoryID
        } else {
            context.insert(ScheduledPayment(title: name, amountCents: cents, dueDate: dueDate,
                                            notes: notes, categoryID: categoryID))
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func pay(_ payment: ScheduledPayment, context: ModelContext) throws {
        guard !payment.isPaid, payment.paidTransactionID == nil else {
            throw FinanceError.invalid("Este pagamento já foi registrado.")
        }
        let categories = try context.fetch(FetchDescriptor<Category>())
        let transaction = Transaction(title: payment.title, amountCents: payment.amountCents,
                                      kind: .expense, date: .now,
                                      category: categories.first { $0.id == payment.categoryID })
        context.insert(transaction)
        payment.isPaid = true
        payment.paidTransactionID = transaction.id
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }

    func delete(_ payment: ScheduledPayment, context: ModelContext, removeRecordedExpense: Bool = false) throws {
        if removeRecordedExpense, let id = payment.paidTransactionID,
           let transaction = try context.fetch(FetchDescriptor<Transaction>()).first(where: { $0.id == id }) {
            guard transaction.card == nil, transaction.kind == .expense else {
                throw FinanceError.invalid("O vínculo deste pagamento não corresponde a uma despesa na conta. Exclua somente o agendamento e revise o extrato.")
            }
            context.delete(transaction)
        }
        context.delete(payment)
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }
}
