import Foundation
import SwiftData
import WidgetKit

@MainActor
enum AppResetService {
    static func reset(context: ModelContext, defaults: UserDefaults = .standard) throws {
        // Finish every fallible fetch before changing anything. One database save
        // removes the financial records and restores the original categories.
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let payments = try context.fetch(FetchDescriptor<InvoicePayment>())
        let scheduled = try context.fetch(FetchDescriptor<ScheduledPayment>())
        let subscriptions = try context.fetch(FetchDescriptor<Subscription>())
        let cards = try context.fetch(FetchDescriptor<CreditCard>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        transactions.forEach { context.delete($0) }
        payments.forEach { context.delete($0) }
        scheduled.forEach { context.delete($0) }
        subscriptions.forEach { context.delete($0) }
        cards.forEach { context.delete($0) }
        Persistence.resetCategories(categories, context: context)
        do { try context.save() } catch { context.rollback(); throw error }

        let revision = defaults.integer(forKey: "ledger.resetRevision") + 1
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ledger.") || key.hasPrefix("reminders.") {
            defaults.removeObject(forKey: key)
        }
        LedgerThemeState.shared.refresh()
        LedgerRouter.shared.reset()
        NotificationService.shared.reset(context: context)
        try? LedgerWidgetStore.clear()
        WidgetSnapshotService.refresh(context: context)
        WidgetCenter.shared.reloadAllTimelines()
        defaults.set(revision, forKey: "ledger.resetRevision")
        FinanceEvents.saved()
    }
}
