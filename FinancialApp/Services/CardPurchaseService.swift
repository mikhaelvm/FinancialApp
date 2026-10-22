import Foundation

struct CardPurchaseGroup: Identifiable {
    let card: CreditCard
    let purchaseID: UUID
    let transactions: [Transaction]
    var id: String { card.id.uuidString + ":" + purchaseID.uuidString }
    var title: String { transactions.first?.title ?? "Compra" }
    var date: Date { transactions.map(\.date).min() ?? .now }
    var amountCents: Int64 { transactions.reduce(0) { $0 + $1.amountCents } }
    var category: Category? { transactions.first?.category }
    var installments: Int { transactions.map(\.totalInstallments).max() ?? 1 }
    var isRecurring: Bool { transactions.contains { $0.isAutomaticRecurrence } }
    var hasRecordedPayment: Bool {
        let dues = Set(transactions.compactMap(\.invoiceDueDate))
        return card.payments.contains { dues.contains($0.invoiceDueDate) && $0.amountCents > 0 }
    }
}

enum CardPurchaseService {
    static func groups(for card: CreditCard) -> [CardPurchaseGroup] {
        Dictionary(grouping: card.transactions, by: \.purchaseID).map { id, rows in
            CardPurchaseGroup(card: card, purchaseID: id, transactions: rows.sorted { $0.installmentNumber < $1.installmentNumber })
        }.sorted { $0.date == $1.date ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.date > $1.date }
    }
    static func groups(for cards: [CreditCard]) -> [CardPurchaseGroup] {
        cards.flatMap { groups(for: $0) }.sorted { $0.date > $1.date }
    }
}
