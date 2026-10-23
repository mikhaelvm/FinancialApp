import AppIntents
import SwiftData
import Foundation

struct TrackrCategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoria"
    static var defaultQuery = TrackrCategoryQuery()
    let id: UUID
    @Property(title: "Nome") var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(category: Category) { id = category.id; name = category.name }
}

struct TrackrCategoryQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [TrackrCategoryEntity] {
        try categories().filter { identifiers.contains($0.id) }.map { TrackrCategoryEntity(category: $0) }
    }
    @MainActor func entities(matching string: String) async throws -> [TrackrCategoryEntity] {
        try categories().filter { $0.name.localizedCaseInsensitiveContains(string) }.map { TrackrCategoryEntity(category: $0) }
    }
    @MainActor func suggestedEntities() async throws -> [TrackrCategoryEntity] {
        try categories().map { TrackrCategoryEntity(category: $0) }
    }
    @MainActor private func categories() throws -> [Category] {
        try AppLockService.shared.requireUnlockedAccess()
        let context = try Persistence.sharedContainer().mainContext
        try Persistence.seed(context: context)
        return try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\Category.name)]))
    }
}

struct TrackrTransactionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Lançamento do Trackr"
    static var defaultQuery = TrackrTransactionQuery()
    let id: UUID
    @Property(title: "Título") var title: String
    @Property(title: "Valor") var amount: String
    @Property(title: "Data") var date: Date
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(amount)")
    }
    init(transaction: Transaction) {
        id = transaction.id; title = transaction.title
        amount = Money.format(transaction.amountCents); date = transaction.date
    }
}

struct TrackrTransactionQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [TrackrTransactionEntity] {
        try transactions().filter { identifiers.contains($0.id) }.map { TrackrTransactionEntity(transaction: $0) }
    }
    @MainActor func entities(matching string: String) async throws -> [TrackrTransactionEntity] {
        try transactions().filter { $0.title.localizedCaseInsensitiveContains(string) }
            .prefix(50).map { TrackrTransactionEntity(transaction: $0) }
    }
    @MainActor func suggestedEntities() async throws -> [TrackrTransactionEntity] {
        try transactions().prefix(10).map { TrackrTransactionEntity(transaction: $0) }
    }
    @MainActor private func transactions() throws -> [Transaction] {
        try AppLockService.shared.requireUnlockedAccess()
        // The search UI represents cash entries. Card purchases remain in their invoice detail.
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.card == nil },
                                                       sortBy: [SortDescriptor(\Transaction.date, order: .reverse)])
        return try Persistence.sharedContainer().mainContext.fetch(descriptor)
    }
}
