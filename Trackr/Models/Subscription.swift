import Foundation
import SwiftData

enum BillingCycle: String, CaseIterable, Identifiable {
    case weekly, monthly, yearly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: return "Semanal"
        case .monthly: return "Mensal"
        case .yearly: return "Anual"
        }
    }
}

@Model
final class Subscription {
    @Attribute(.unique) var id: UUID
    var title: String
    var amountCents: Int64
    var cycleRaw: String
    /// Anchor + index preserve the 31st and February 29 across short months.
    var anchorDate: Date
    var scheduleID: UUID
    var nextOccurrenceIndex: Int
    var nextRenewalDate: Date
    var isActive: Bool
    var card: CreditCard?
    var category: Category?
    @Relationship(deleteRule: .nullify, inverse: \Transaction.subscription)
    var transactions: [Transaction] = []

    init(title: String, amountCents: Int64, cycle: BillingCycle,
         nextRenewalDate: Date, category: Category?, card: CreditCard?) {
        id = UUID()
        self.title = title
        self.amountCents = amountCents
        cycleRaw = cycle.rawValue
        anchorDate = nextRenewalDate
        scheduleID = UUID()
        nextOccurrenceIndex = 0
        self.nextRenewalDate = nextRenewalDate
        isActive = true
        self.category = category
        self.card = card
    }

    var cycle: BillingCycle { BillingCycle(rawValue: cycleRaw) ?? .monthly }
    var monthlyEquivalentCents: Double {
        switch cycle {
        case .weekly: return Double(amountCents) * 52 / 12
        case .monthly: return Double(amountCents)
        case .yearly: return Double(amountCents) / 12
        }
    }
}
