import AppIntents
import SwiftData
import Foundation

struct LedgerCategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoria"
    static var defaultQuery = LedgerCategoryQuery()
    let id: UUID
    @Property(title: "Nome") var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(category: Category) { id = category.id; name = category.name }
}

struct LedgerCategoryQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [LedgerCategoryEntity] {
        try categories().filter { identifiers.contains($0.id) }.map { LedgerCategoryEntity(category: $0) }
    }
    @MainActor func entities(matching string: String) async throws -> [LedgerCategoryEntity] {
        try categories().filter { $0.name.localizedCaseInsensitiveContains(string) }.map { LedgerCategoryEntity(category: $0) }
    }
    @MainActor func suggestedEntities() async throws -> [LedgerCategoryEntity] {
        try categories().map { LedgerCategoryEntity(category: $0) }
    }
    @MainActor private func categories() throws -> [Category] {
        try AppLockService.shared.requireUnlockedAccess()
        let context = try Persistence.sharedContainer().mainContext
        try Persistence.seed(context: context)
        return try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\Category.name)]))
    }
}

struct LedgerTransactionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Lançamento do Ledger"
    static var defaultQuery = LedgerTransactionQuery()
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

struct LedgerTransactionQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [LedgerTransactionEntity] {
        try transactions().filter { identifiers.contains($0.id) }.map { LedgerTransactionEntity(transaction: $0) }
    }
    @MainActor func entities(matching string: String) async throws -> [LedgerTransactionEntity] {
        try transactions().filter { $0.title.localizedCaseInsensitiveContains(string) }
            .prefix(50).map { LedgerTransactionEntity(transaction: $0) }
    }
    @MainActor func suggestedEntities() async throws -> [LedgerTransactionEntity] {
        try transactions().prefix(10).map { LedgerTransactionEntity(transaction: $0) }
    }
    @MainActor private func transactions() throws -> [Transaction] {
        try AppLockService.shared.requireUnlockedAccess()
        // The search UI represents cash entries. Card purchases remain in their invoice detail.
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.card == nil },
                                                       sortBy: [SortDescriptor(\Transaction.date, order: .reverse)])
        return try Persistence.sharedContainer().mainContext.fetch(descriptor)
    }
}
