import Foundation
import SwiftData

@Model
final class CreditCard {
    @Attribute(.unique) var id: UUID
    var name: String
    var limitCents: Int64
    var closingDay: Int
    var dueDay: Int
    @Relationship(deleteRule: .cascade, inverse: \Transaction.card)
    var transactions: [Transaction] = []
    @Relationship(deleteRule: .nullify, inverse: \Subscription.card)
    var subscriptions: [Subscription] = []
    @Relationship(deleteRule: .cascade, inverse: \InvoicePayment.card)
    var payments: [InvoicePayment] = []

    init(name: String, limitCents: Int64, closingDay: Int, dueDay: Int) {
        id = UUID()
        self.name = name
        self.limitCents = limitCents
        self.closingDay = closingDay
        self.dueDay = dueDay
    }

    var usedLimitCents: Int64 {
        let charged = transactions.reduce(Int64(0)) { $0 + $1.amountCents }
        let paid = payments.reduce(Int64(0)) { $0 + $1.amountCents }
        return max(0, charged - paid)
    }
    var availableLimitCents: Int64 { max(0, limitCents - usedLimitCents) }
}
