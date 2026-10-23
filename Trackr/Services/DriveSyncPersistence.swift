import Foundation
import SwiftData

@MainActor enum DriveSyncPersistence {
    /// Apply a complete merged graph in one save. Reuse live model objects so
    /// open detail screens don't lose their references during a refresh.
    static func apply(_ backup: TrackrBackup, context: ModelContext) throws {
        try backup.validate()
        let oldCategories = try context.fetch(FetchDescriptor<Category>())
        let oldCards = try context.fetch(FetchDescriptor<CreditCard>())
        let oldSubscriptions = try context.fetch(FetchDescriptor<Subscription>())
        let oldTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let oldPayments = try context.fetch(FetchDescriptor<InvoicePayment>())
        let oldScheduled = try context.fetch(FetchDescriptor<ScheduledPayment>())
        var categories: [UUID: Category] = [:]
        var cards: [UUID: CreditCard] = [:]
        var subscriptions: [UUID: Subscription] = [:]
        var keptTransactions: Set<PersistentIdentifier> = []
        var keptCategories: Set<PersistentIdentifier> = []
        let oldReceipts = Dictionary(oldScheduled.compactMap { bill in bill.paidTransactionID.map { ($0, bill.id) } }, uniquingKeysWith: { a, _ in a })
        let byKey = Dictionary(oldTransactions.compactMap { model in model.recurrenceKey.map { ($0, model) } }, uniquingKeysWith: { a, _ in a })
        do {
            for row in backup.categories {
                let model = oldCategories.first { $0.id == row.id } ?? oldCategories.first {
                    $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")) ==
                    row.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
                } ?? Category(name: row.name, symbol: row.symbol, colorName: row.colorName)
                if model.modelContext == nil { context.insert(model) }
                model.id = row.id; model.name = row.name; model.symbol = row.symbol; model.colorName = row.colorName
                categories[row.id] = model; keptCategories.insert(model.persistentModelID)
            }
            for row in backup.cards {
                let model = oldCards.first { $0.id == row.id } ?? CreditCard(name: row.name, limitCents: row.limitCents, closingDay: row.closingDay, dueDay: row.dueDay)
                if model.modelContext == nil { context.insert(model) }
                model.id = row.id; model.name = row.name; model.limitCents = row.limitCents
                model.closingDay = row.closingDay; model.dueDay = row.dueDay; cards[row.id] = model
            }
            for row in backup.subscriptions {
                let model = oldSubscriptions.first { $0.id == row.id } ?? Subscription(title: row.title, amountCents: row.amountCents,
                    cycle: BillingCycle(rawValue: row.cycleRaw)!, nextRenewalDate: row.nextRenewalDate, category: nil, card: nil)
                if model.modelContext == nil { context.insert(model) }
                model.id = row.id; model.title = row.title; model.amountCents = row.amountCents; model.cycleRaw = row.cycleRaw
                model.scheduleID = row.scheduleID; model.anchorDate = row.anchorDate; model.nextOccurrenceIndex = row.nextOccurrenceIndex
                model.nextRenewalDate = row.nextRenewalDate; model.isActive = row.isActive
                model.category = row.categoryID.flatMap { categories[$0] }; model.card = row.cardID.flatMap { cards[$0] }
                subscriptions[row.id] = model
            }
            for row in backup.transactions {
                let existing = oldTransactions.first { $0.id == row.id } ?? row.recurrenceKey.flatMap { byKey[$0] } ?? oldTransactions.first {
                    guard let billID = oldReceipts[$0.id] else { return false }
                    return DriveSyncState.stableID("scheduledReceipt:" + billID.uuidString) == row.id
                }
                let model = existing ?? Transaction(title: row.title, amountCents: row.amountCents, kind: TransactionKind(rawValue: row.kindRaw)!, date: row.date)
                if model.modelContext == nil { context.insert(model) }
                model.id = row.id; model.title = row.title; model.amountCents = row.amountCents; model.kindRaw = row.kindRaw; model.date = row.date
                model.purchaseID = row.purchaseID; model.installmentNumber = row.installmentNumber; model.totalInstallments = row.totalInstallments
                model.invoiceDueDate = row.dueDate; model.invoiceClosingDate = row.closingDate; model.recurrenceKey = row.recurrenceKey
                model.category = row.categoryID.flatMap { categories[$0] }; model.card = row.cardID.flatMap { cards[$0] }
                model.subscription = row.subscriptionID.flatMap { subscriptions[$0] }
                keptTransactions.insert(model.persistentModelID)
            }
            for row in backup.payments {
                guard let card = row.cardID.flatMap({ cards[$0] }) else { continue }
                let model = oldPayments.first { $0.id == row.id } ?? InvoicePayment(card: card, invoiceDueDate: row.dueDate, date: row.date, amountCents: row.amountCents)
                if model.modelContext == nil { context.insert(model) }
                model.id = row.id; model.card = card; model.invoiceDueDate = row.dueDate; model.date = row.date; model.amountCents = row.amountCents
            }
            for row in backup.scheduled {
                let model = oldScheduled.first { $0.id == row.id } ?? ScheduledPayment(title: row.title, amountCents: row.amountCents, dueDate: row.dueDate)
                if model.modelContext == nil { context.insert(model) }
                model.id = row.id; model.title = row.title; model.notes = row.notes; model.amountCents = row.amountCents; model.dueDate = row.dueDate
                model.categoryID = row.categoryID; model.isPaid = row.isPaid; model.paidTransactionID = row.paidTransactionID
            }
            let paymentIDs = Set(backup.payments.map(\.id)), scheduledIDs = Set(backup.scheduled.map(\.id))
            oldTransactions.filter { !keptTransactions.contains($0.persistentModelID) }.forEach { context.delete($0) }
            oldPayments.filter { !paymentIDs.contains($0.id) }.forEach { context.delete($0) }
            oldScheduled.filter { !scheduledIDs.contains($0.id) }.forEach { context.delete($0) }
            oldSubscriptions.filter { subscriptions[$0.id] == nil }.forEach { context.delete($0) }
            oldCards.filter { cards[$0.id] == nil }.forEach { context.delete($0) }
            oldCategories.filter { !keptCategories.contains($0.persistentModelID) }.forEach { context.delete($0) }
            try context.save()
        } catch { context.rollback(); throw error }
        UserDefaults.standard.set((backup.dismissedPayments ?? []).sorted().joined(separator: "\n"), forKey: PaymentDismissalStore.key)
        FinanceEvents.saved()
    }
}
