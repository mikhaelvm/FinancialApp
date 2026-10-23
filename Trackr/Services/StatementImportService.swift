import Foundation
import SwiftData

extension Transaction {
    var isImportedStatement: Bool { recurrenceKey?.hasPrefix("statement:") == true }
    var isAutomaticRecurrence: Bool { recurrenceKey != nil && !isImportedStatement }
}

@MainActor
enum StatementImportService {
    static func prepare(_ rows: [StatementRow], context: ModelContext, today: Date = .now) throws -> [StatementRow] {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let existing = Set(transactions.compactMap(\.recurrenceKey))
        let signatures = Set(transactions.filter { $0.card == nil }.map {
            "\(StatementParser.dayKey($0.date))|\($0.kind == .expense ? -$0.amountCents : $0.amountCents)|\(StatementParser.normalize($0.title))"
        })
        let categories = try context.fetch(FetchDescriptor<Category>())
        let payments = try context.fetch(FetchDescriptor<InvoicePayment>())
        var invoicePayments = Set(payments.map {
            "\(StatementParser.dayKey($0.date))|\(-$0.amountCents)"
        })
        var originalPayments = Dictionary(uniqueKeysWithValues: payments.map { ($0.id.uuidString, ($0.date, $0.amountCents)) })
        for transaction in transactions where transaction.card == nil && transaction.kind == .expense {
            guard let key = transaction.recurrenceKey, key.hasPrefix("preserved-card-payment:") else { continue }
            let id = String(key.dropFirst("preserved-card-payment:".count).prefix(36))
            guard UUID(uuidString: id) != nil else { continue }
            let previous = originalPayments[id]?.1 ?? 0
            originalPayments[id] = (transaction.date, previous + transaction.amountCents)
        }
        for (date, cents) in originalPayments.values { invoicePayments.insert("\(StatementParser.dayKey(date))|\(-cents)") }
        let scheduledIDs = Set(try context.fetch(FetchDescriptor<ScheduledPayment>()).compactMap(\.paidTransactionID))
        let managedCash = Set(transactions.filter { $0.card == nil && ($0.isAutomaticRecurrence || $0.isImportedStatement || scheduledIDs.contains($0.id)) }.map {
            "\(StatementParser.dayKey($0.date))|\($0.kind == .expense ? -$0.amountCents : $0.amountCents)"
        })
        var seen = existing
        return rows.map { original in
            var row = original
            row.isDuplicate = !seen.insert(row.importKey).inserted
                || signatures.contains("\(StatementParser.dayKey(row.date))|\(row.signedCents)|\(StatementParser.normalize(row.title))")
                || invoicePayments.contains("\(StatementParser.dayKey(row.date))|\(row.signedCents)")
                || managedCash.contains("\(StatementParser.dayKey(row.date))|\(row.signedCents)")
            row.selected = !row.isDuplicate && !row.requiresReview && row.date <= FinanceDate.day(today)
            row.importAsNew = false
            let name = StatementParser.normalize(row.title)
            let rules: [(String, [String])] = [
                ("Streaming", ["netflix", "spotify", "disney", "primevideo"]),
                ("Alimentação", ["supermercado", "restaurante", "ifood", "padaria"]),
                ("Transporte", ["uber", "combustivel", "estacionamento", "posto"]),
                ("Saúde", ["farmacia", "drogaria", "clinica"])
            ]
            let isSalary = row.kind == .income && ["salario", "prolabore", "folhadepagamento"].contains { name.contains($0) }
            let suggested = isSalary ? "Salário" : rules.first { _, terms in terms.contains { name.contains($0) } }?.0
            row.categoryID = categories.first { $0.name == suggested }?.id
            return row
        }
    }

    static func commit(_ rows: [StatementRow], context: ModelContext, today: Date = .now) throws -> Int {
        let selected = rows.filter(\.selected)
        guard selected.allSatisfy({ $0.signedCents != 0 && $0.signedCents != Int64.min && abs($0.signedCents) <= Money.maximumCents && $0.date <= FinanceDate.day(today) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw FinanceError.invalid("Revise os valores e datas. Lançamentos futuros não são movimentos realizados.")
        }
        var keys = Set(try context.fetch(FetchDescriptor<Transaction>()).compactMap(\.recurrenceKey))
        let categories = try context.fetch(FetchDescriptor<Category>())
        var count = 0
        for row in selected {
            let key = row.importAsNew ? row.importKey + ":copy:" + UUID().uuidString : row.importKey
            guard keys.insert(key).inserted else { continue }
            context.insert(Transaction(title: row.title, amountCents: abs(row.signedCents), kind: row.kind, date: row.date,
                                       category: categories.first { $0.id == row.categoryID }, recurrenceKey: key))
            count += 1
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
        return count
    }
}
