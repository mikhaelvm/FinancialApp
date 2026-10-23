import Foundation
import SwiftData

enum FinanceSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CreditCard.self, Transaction.self, Subscription.self, Category.self, InvoicePayment.self]
    }
}

enum FinanceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FinanceSchemaV1.self, FinanceSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: FinanceSchemaV1.self, toVersion: FinanceSchemaV2.self)]
    }
}

// V1 entities are unchanged. V2 only adds the standalone manual-bill entity.
enum FinanceSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        FinanceSchemaV1.models + [ScheduledPayment.self]
    }
}

enum Persistence {
    @MainActor private static var liveContainer: ModelContainer?

    @MainActor static func sharedContainer() throws -> ModelContainer {
        if let liveContainer { return liveContainer }
        let container = try makeContainer()
        liveContainer = container
        return container
    }

    @MainActor static func makeContainer(inMemory: Bool = false, storageURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinanceSchemaV2.self)
        let configuration: ModelConfiguration
        if let storageURL {
            configuration = ModelConfiguration(schema: schema, url: storageURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: FinanceMigrationPlan.self,
                                  configurations: [configuration])
    }

    @MainActor static func seed(context: ModelContext) throws {
        let existing = Set(try context.fetch(FetchDescriptor<Category>()).map(\.name))
        insertDefaultCategories(context: context, excluding: existing)
        try context.save()
    }

    @MainActor static func insertDefaultCategories(context: ModelContext, excluding existing: Set<String> = []) {
        for (name, symbol, color) in defaultCategories where !existing.contains(name) {
            context.insert(Category(name: name, symbol: symbol, colorName: color))
        }
    }

    @MainActor static func resetCategories(_ existing: [Category], context: ModelContext) {
        let names = Set(defaultCategories.map { $0.0 })
        for category in existing where !names.contains(category.name) { context.delete(category) }
        for (name, symbol, color) in defaultCategories {
            if let category = existing.first(where: { $0.name == name }) {
                category.symbol = symbol; category.colorName = color
            } else { context.insert(Category(name: name, symbol: symbol, colorName: color)) }
        }
    }

    private static let defaultCategories = [
            ("Streaming", "play.tv.fill", "purple"),
            ("Alimentação", "fork.knife", "orange"),
            ("Moradia", "house.fill", "blue"),
            ("Transporte", "car.fill", "teal"),
            ("Saúde", "heart.fill", "pink"),
            ("Lazer", "party.popper.fill", "purple"),
            ("Educação", "book.fill", "blue"),
            ("Salário", "banknote.fill", "green"),
            ("Outros", "square.grid.2x2.fill", "teal")
        ]
}
