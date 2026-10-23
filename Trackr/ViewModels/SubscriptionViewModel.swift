import Foundation
import Observation
import SwiftData

enum RecurrenceBillingAction: String, CaseIterable, Identifiable {
    case keep = "Cobrar normalmente", skipNext = "Suspender próxima cobrança", pause = "Pausar indefinidamente"
    var id: String { rawValue }
}

@MainActor @Observable
final class SubscriptionViewModel {
    func save(context: ModelContext, subscription: Subscription? = nil, title: String,
              amountText: String, cycle: BillingCycle, renewalDate: Date,
              category: Category?, card: CreditCard?, billingAction: RecurrenceBillingAction? = nil) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let cents = Money.parse(amountText),
              FinanceDate.day(renewalDate) >= FinanceDate.day(.now) else {
            throw FinanceError.invalid("Informe título, valor positivo e renovação a partir de hoje.")
        }
        let renewal = FinanceDate.day(renewalDate)
        if let subscription {
            let oldCycle = subscription.cycle
            subscription.title = name
            subscription.amountCents = cents
            subscription.cycleRaw = cycle.rawValue
            subscription.category = category
            subscription.card = card
            // Reset the schedule only when its date or cycle changes; existing charges stay intact.
            if renewal != subscription.nextRenewalDate || oldCycle != cycle {
                subscription.anchorDate = renewal
                subscription.nextOccurrenceIndex = 0
                // A new schedule needs a distinct identity to avoid reusing occurrence keys.
                subscription.scheduleID = UUID()
            }
            subscription.nextRenewalDate = renewal
            if let billingAction {
                subscription.isActive = billingAction != .pause
                if billingAction == .skipNext {
                    subscription.nextOccurrenceIndex += 1
                    subscription.nextRenewalDate = RecurrenceEngine().date(for: subscription, index: subscription.nextOccurrenceIndex)
                }
            }
        } else {
            context.insert(Subscription(title: name, amountCents: cents, cycle: cycle,
                                         nextRenewalDate: renewal, category: category, card: card))
        }
        do { try RecurrenceEngine().synchronize(context: context) }
        catch { context.rollback(); throw error }
    }

    func setActive(_ active: Bool, subscription: Subscription, context: ModelContext) throws {
        if active {
            // Resuming starts today; inactive time is not charged retroactively.
            subscription.scheduleID = UUID()
            subscription.anchorDate = FinanceDate.day(.now)
            subscription.nextOccurrenceIndex = 0
            subscription.nextRenewalDate = subscription.anchorDate
        }
        subscription.isActive = active
        do { try RecurrenceEngine().synchronize(context: context) }
        catch { context.rollback(); throw error }
    }

    func delete(_ subscription: Subscription, context: ModelContext) throws {
        context.delete(subscription)
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }
}
