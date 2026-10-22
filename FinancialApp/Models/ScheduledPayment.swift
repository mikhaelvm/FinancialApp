import Foundation
import SwiftData

/// A manual bill is a commitment until the user records its payment.
/// Recurring bills continue to use Subscription, without duplicating their cash entries.
@Model
final class ScheduledPayment {
    @Attribute(.unique) var id: UUID
    var title: String
    var amountCents: Int64
    var dueDate: Date
    var notes: String
    var categoryID: UUID?
    var isPaid: Bool
    var paidTransactionID: UUID?

    init(title: String, amountCents: Int64, dueDate: Date, notes: String = "", categoryID: UUID? = nil) {
        id = UUID()
        self.title = title
        self.amountCents = amountCents
        self.dueDate = FinanceDate.day(dueDate)
        self.notes = notes
        self.categoryID = categoryID
        isPaid = false
        paidTransactionID = nil
    }
}
