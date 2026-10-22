import Foundation
import SwiftData

struct LedgerBackup: Codable {
    var formatVersion = 1
    var createdAt = Date.now
    let categories: [CategoryRecord]
    let cards: [CardRecord]
    let subscriptions: [SubscriptionRecord]
    let transactions: [TransactionRecord]
    let payments: [PaymentRecord]
    let scheduled: [ScheduledRecord]
    var count: Int { categories.count + cards.count + subscriptions.count + transactions.count + payments.count + scheduled.count }

    struct CategoryRecord: Codable { let id: UUID; let name, symbol, colorName: String }
    struct CardRecord: Codable { let id: UUID; let name: String; let limitCents: Int64; let closingDay, dueDay: Int }
    struct SubscriptionRecord: Codable {
        let id, scheduleID: UUID
        let title, cycleRaw: String
        let amountCents: Int64
        let anchorDate, nextRenewalDate: Date
        let nextOccurrenceIndex: Int
        let isActive: Bool
        let categoryID, cardID: UUID?
    }
    struct TransactionRecord: Codable {
        let id, purchaseID: UUID
        let title, kindRaw: String
        let amountCents: Int64
        let date: Date
        let dueDate, closingDate: Date?
        let installmentNumber, totalInstallments: Int
        let recurrenceKey: String?
        let categoryID, cardID, subscriptionID: UUID?
    }
    struct PaymentRecord: Codable { let id: UUID; let cardID: UUID?; let dueDate, date: Date; let amountCents: Int64 }
    struct ScheduledRecord: Codable {
        let id: UUID; let title, notes: String; let amountCents: Int64; let dueDate: Date
        let categoryID, paidTransactionID: UUID?; let isPaid: Bool
    }

    func validate() throws {
        func check(_ condition: Bool) throws {
            if !condition { throw FinanceError.invalid("O backup contém dados inválidos ou referências incompletas.") }
        }
        func validDate(_ date: Date) -> Bool {
            date.timeIntervalSince1970.isFinite && (1...9999).contains(FinanceDate.calendar.component(.year, from: date))
        }
        func amount(_ value: Int64) -> Bool { value > 0 && value <= Money.maximumCents }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard formatVersion == 1 else { throw FinanceError.invalid("Versão de backup incompatível. Atualize o Ledger.") }
        try check(count <= 100_000)
        for ids in [categories.map(\.id), cards.map(\.id), subscriptions.map(\.id), transactions.map(\.id), payments.map(\.id), scheduled.map(\.id)] { try check(unique(ids)) }
        try check(Set(categories.map { $0.name.lowercased() }).count == categories.count)
        let categoryIDs = Set(categories.map(\.id)), cardIDs = Set(cards.map(\.id))
        let subscriptionIDs = Set(subscriptions.map(\.id)), transactionIDs = Set(transactions.map(\.id))
        func reference(_ id: UUID?, in ids: Set<UUID>) -> Bool { id == nil || ids.contains(id!) }
        for row in categories { try check(!row.name.isEmpty && !row.symbol.isEmpty) }
        for row in cards { try check(!row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount(row.limitCents) && (1...31).contains(row.closingDay) && (1...31).contains(row.dueDay)) }
        for row in subscriptions {
            try check(!row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount(row.amountCents) && BillingCycle(rawValue: row.cycleRaw) != nil && (0...20_000).contains(row.nextOccurrenceIndex))
            try check(validDate(row.anchorDate) && validDate(row.nextRenewalDate))
            try check(reference(row.categoryID, in: categoryIDs) && reference(row.cardID, in: cardIDs))
        }
        for row in transactions {
            try check(!row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount(row.amountCents) && TransactionKind(rawValue: row.kindRaw) != nil && validDate(row.date))
            try check((1...120).contains(row.totalInstallments) && (1...row.totalInstallments).contains(row.installmentNumber))
            try check(reference(row.categoryID, in: categoryIDs) && reference(row.cardID, in: cardIDs) && reference(row.subscriptionID, in: subscriptionIDs))
            if row.cardID != nil { try check(row.kindRaw == TransactionKind.expense.rawValue && row.dueDate != nil && row.closingDate != nil) }
            if let date = row.dueDate { try check(validDate(date)) }
            if let date = row.closingDate { try check(validDate(date)) }
        }
        for row in payments { try check(row.cardID != nil && amount(row.amountCents) && validDate(row.date) && validDate(row.dueDate) && reference(row.cardID, in: cardIDs)) }
        for row in scheduled {
            try check(!row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount(row.amountCents) && validDate(row.dueDate) && reference(row.categoryID, in: categoryIDs))
            try check(reference(row.paidTransactionID, in: transactionIDs) && (!row.isPaid || row.paidTransactionID != nil))
        }
        let keys = transactions.compactMap(\.recurrenceKey)
        try check(Set(keys).count == keys.count)
    }
}

@MainActor
enum BackupService {
    static func snapshot(context: ModelContext) throws -> LedgerBackup {
        LedgerBackup(
            categories: try context.fetch(FetchDescriptor<Category>()).map { .init(id: $0.id, name: $0.name, symbol: $0.symbol, colorName: $0.colorName) },
            cards: try context.fetch(FetchDescriptor<CreditCard>()).map { .init(id: $0.id, name: $0.name, limitCents: $0.limitCents, closingDay: $0.closingDay, dueDay: $0.dueDay) },
            subscriptions: try context.fetch(FetchDescriptor<Subscription>()).map { .init(id: $0.id, scheduleID: $0.scheduleID, title: $0.title, cycleRaw: $0.cycleRaw, amountCents: $0.amountCents, anchorDate: $0.anchorDate, nextRenewalDate: $0.nextRenewalDate, nextOccurrenceIndex: $0.nextOccurrenceIndex, isActive: $0.isActive, categoryID: $0.category?.id, cardID: $0.card?.id) },
            transactions: try context.fetch(FetchDescriptor<Transaction>()).map { .init(id: $0.id, purchaseID: $0.purchaseID, title: $0.title, kindRaw: $0.kindRaw, amountCents: $0.amountCents, date: $0.date, dueDate: $0.invoiceDueDate, closingDate: $0.invoiceClosingDate, installmentNumber: $0.installmentNumber, totalInstallments: $0.totalInstallments, recurrenceKey: $0.recurrenceKey, categoryID: $0.category?.id, cardID: $0.card?.id, subscriptionID: $0.subscription?.id) },
            payments: try context.fetch(FetchDescriptor<InvoicePayment>()).map { .init(id: $0.id, cardID: $0.card?.id, dueDate: $0.invoiceDueDate, date: $0.date, amountCents: $0.amountCents) },
            scheduled: try context.fetch(FetchDescriptor<ScheduledPayment>()).map { .init(id: $0.id, title: $0.title, notes: $0.notes, amountCents: $0.amountCents, dueDate: $0.dueDate, categoryID: $0.categoryID, paidTransactionID: $0.paidTransactionID, isPaid: $0.isPaid) })
    }

    static func encode(_ backup: LedgerBackup) throws -> Data {
        try backup.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }
    static func decode(_ data: Data) throws -> LedgerBackup {
        guard data.count <= 25_000_000 else { throw FinanceError.invalid("O backup excede o limite de 25 MB.") }
        let backup = try JSONDecoder().decode(LedgerBackup.self, from: data)
        try backup.validate()
        return backup
    }

    /// Merge by stable IDs; existing records win. Nothing is erased or silently overwritten.
    static func restore(_ backup: LedgerBackup, context: ModelContext) throws -> Int {
        try backup.validate()
        var inserted = 0
        var categories = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Category>()).map { ($0.id, $0) })
        var cards = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CreditCard>()).map { ($0.id, $0) })
        var subscriptions = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Subscription>()).map { ($0.id, $0) })
        // Complete every fallible read before inserting anything. A read failure must
        // never leave a partially restored graph for SwiftData autosave to persist.
        let currentTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let currentPayments = try context.fetch(FetchDescriptor<InvoicePayment>())
        let currentScheduled = try context.fetch(FetchDescriptor<ScheduledPayment>())
        let isFreshStore = cards.isEmpty && subscriptions.isEmpty && currentTransactions.isEmpty && currentPayments.isEmpty && currentScheduled.isEmpty
        let byKey = Dictionary(currentTransactions.compactMap { model in model.recurrenceKey.map { ($0, model) } }, uniquingKeysWith: { first, _ in first })
        var categoryMap: [UUID: UUID] = [:]
        for row in backup.categories {
            if let existing = categories[row.id] ?? categories.values.first(where: { $0.name.localizedCaseInsensitiveCompare(row.name) == .orderedSame }) {
                categoryMap[row.id] = existing.id
                if isFreshStore { existing.symbol = row.symbol; existing.colorName = row.colorName }
            } else {
                let model = Category(name: row.name, symbol: row.symbol, colorName: row.colorName)
                model.id = row.id; context.insert(model); categories[row.id] = model; categoryMap[row.id] = row.id; inserted += 1
            }
        }
        func category(_ id: UUID?) -> Category? { id.flatMap { categoryMap[$0] }.flatMap { categories[$0] } }
        for row in backup.cards where cards[row.id] == nil {
            let model = CreditCard(name: row.name, limitCents: row.limitCents, closingDay: row.closingDay, dueDay: row.dueDay)
            model.id = row.id; context.insert(model); cards[row.id] = model; inserted += 1
        }
        for row in backup.subscriptions where subscriptions[row.id] == nil {
            let model = Subscription(title: row.title, amountCents: row.amountCents, cycle: BillingCycle(rawValue: row.cycleRaw)!, nextRenewalDate: row.nextRenewalDate, category: category(row.categoryID), card: row.cardID.flatMap { cards[$0] })
            model.id = row.id; model.scheduleID = row.scheduleID; model.anchorDate = row.anchorDate
            model.nextOccurrenceIndex = row.nextOccurrenceIndex; model.isActive = row.isActive
            context.insert(model); subscriptions[row.id] = model; inserted += 1
        }
        var transactionIDs = Set(currentTransactions.map(\.id))
        var transactionMap: [UUID: UUID] = [:]
        for row in backup.transactions {
            if transactionIDs.contains(row.id) { transactionMap[row.id] = row.id; continue }
            if let key = row.recurrenceKey, let existing = byKey[key] {
                transactionMap[row.id] = existing.id; continue
            }
            let model = Transaction(title: row.title, amountCents: row.amountCents, kind: TransactionKind(rawValue: row.kindRaw)!, date: row.date,
                                    category: category(row.categoryID), card: row.cardID.flatMap { cards[$0] }, installmentNumber: row.installmentNumber,
                                    totalInstallments: row.totalInstallments, purchaseID: row.purchaseID, invoiceDueDate: row.dueDate,
                                    invoiceClosingDate: row.closingDate, subscription: row.subscriptionID.flatMap { subscriptions[$0] }, recurrenceKey: row.recurrenceKey)
            model.id = row.id; context.insert(model); transactionIDs.insert(row.id); transactionMap[row.id] = row.id; inserted += 1
        }
        let paymentIDs = Set(currentPayments.map(\.id))
        for row in backup.payments where !paymentIDs.contains(row.id) {
            guard let card = row.cardID.flatMap({ cards[$0] }) else { continue }
            let model = InvoicePayment(card: card, invoiceDueDate: row.dueDate, date: row.date, amountCents: row.amountCents)
            model.id = row.id; context.insert(model); inserted += 1
        }
        let scheduledIDs = Set(currentScheduled.map(\.id))
        for row in backup.scheduled where !scheduledIDs.contains(row.id) {
            let model = ScheduledPayment(title: row.title, amountCents: row.amountCents, dueDate: row.dueDate, notes: row.notes, categoryID: category(row.categoryID)?.id)
            model.id = row.id; model.isPaid = row.isPaid; model.paidTransactionID = row.paidTransactionID.flatMap { transactionMap[$0] }
            context.insert(model); inserted += 1
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
        return inserted
    }

    static func csv(context: ModelContext) throws -> Data {
        func cell(_ value: String) -> String {
            var safe = value
            let isNumber = safe.range(of: #"^-?\d+(,\d{1,2})?$"#, options: .regularExpression) != nil
            if let first = safe.first, "=+-@".contains(first), !isNumber { safe = "'" + safe }
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["Data;Descrição;Natureza;Valor;Categoria;Cartão;Parcela;Vencimento"]
        let formatter = DateFormatter()
        formatter.calendar = FinanceDate.calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        for row in try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\Transaction.date)])) {
            let date = formatter.string(from: row.date)
            let due = row.invoiceDueDate.map { formatter.string(from: $0) } ?? ""
            let amount = (row.kind == .expense ? "-" : "") + Money.input(row.amountCents)
            lines.append([date, row.title, row.kind.title, amount, row.category?.name ?? "", row.card?.name ?? "", "\(row.installmentNumber)/\(row.totalInstallments)", due].map(cell).joined(separator: ";"))
        }
        return Data(("\u{feff}" + lines.joined(separator: "\r\n")).utf8)
    }
}
