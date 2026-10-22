import Foundation
import SwiftData

enum TransactionKind: String, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? "Despesa" : "Receita" }
}

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Always positive; integer centavos avoid floating point rounding.
    var amountCents: Int64
    var kindRaw: String
    var date: Date
    /// Snapshot of the due date. Card configuration changes never move old charges.
    var invoiceDueDate: Date?
    var invoiceClosingDate: Date?
    var installmentNumber: Int
    var totalInstallments: Int
    var purchaseID: UUID
    /// Stable renewal key prevents a second launch from billing the same occurrence.
    var recurrenceKey: String?
    var card: CreditCard?
    var category: Category?
    var subscription: Subscription?

    init(title: String, amountCents: Int64, kind: TransactionKind, date: Date,
         category: Category? = nil, card: CreditCard? = nil,
         installmentNumber: Int = 1, totalInstallments: Int = 1,
         purchaseID: UUID = UUID(), invoiceDueDate: Date? = nil,
         invoiceClosingDate: Date? = nil, subscription: Subscription? = nil,
         recurrenceKey: String? = nil) {
        id = UUID()
        self.title = title
        self.amountCents = amountCents
        kindRaw = kind.rawValue
        self.date = date
        self.category = category
        self.card = card
        self.installmentNumber = installmentNumber
        self.totalInstallments = totalInstallments
        self.purchaseID = purchaseID
        self.invoiceDueDate = invoiceDueDate
        self.invoiceClosingDate = invoiceClosingDate
        self.subscription = subscription
        self.recurrenceKey = recurrenceKey
    }

    var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
}
