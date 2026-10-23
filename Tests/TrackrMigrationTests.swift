import XCTest
import SwiftData
@testable import Trackr
@testable import class Trackr.Category

@MainActor
final class TrackrMigrationTests: XCTestCase {
    func testInstalledV1StoreMigratesWithoutLosingItsRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("default.store")
        let originalCardID: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: FinanceSchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let card = CreditCard(name: "Meu cartão", limitCents: 500_000, closingDay: 20, dueDay: 25)
            container.mainContext.insert(card)
            container.mainContext.insert(Transaction(title: "Saldo inicial", amountCents: 100_000, kind: .income, date: .now))
            try container.mainContext.save()
            return card.id
        }
        let upgraded = try Persistence.makeContainer(storageURL: url)
        let cards = try upgraded.mainContext.fetch(FetchDescriptor<CreditCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.id, originalCardID)
        XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<ScheduledPayment>()), 0)
        upgraded.mainContext.insert(ScheduledPayment(title: "Conta nova", amountCents: 1000, dueDate: .now))
        try upgraded.mainContext.save()
        XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<ScheduledPayment>()), 1)
    }
}
