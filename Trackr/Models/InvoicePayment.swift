import Foundation
import SwiftData

@Model
final class InvoicePayment {
    @Attribute(.unique) var id: UUID
    var invoiceDueDate: Date
    var date: Date
    var amountCents: Int64
    var card: CreditCard?

    init(card: CreditCard, invoiceDueDate: Date, date: Date, amountCents: Int64) {
        id = UUID()
        self.card = card
        self.invoiceDueDate = invoiceDueDate
        self.date = date
        self.amountCents = amountCents
    }
}
