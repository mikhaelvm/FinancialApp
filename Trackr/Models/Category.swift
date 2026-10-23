import SwiftUI
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var symbol: String
    var colorName: String
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []
    @Relationship(deleteRule: .nullify, inverse: \Subscription.category)
    var subscriptions: [Subscription] = []

    init(name: String, symbol: String, colorName: String) {
        id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
    }

    var color: Color {
        switch colorName {
        case "purple": return .purple
        case "orange": return .orange
        case "blue": return .blue
        case "green": return .green
        case "pink": return .pink
        case "red": return .red
        default: return .teal
        }
    }
}
