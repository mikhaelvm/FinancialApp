import Foundation

struct LedgerWidgetPayment: Codable, Identifiable {
    let id: String
    let title: String
    let date: Date
    let cents: Int64
}

struct LedgerWidgetSnapshot: Codable {
    let updatedAt: Date
    let month: Date
    let balance: Int64
    let income: Int64
    let expenses: Int64
    let pendingInvoices: Int64
    let projectedBalance: Int64
    let upcoming: [LedgerWidgetPayment]
    let hidesAmounts: Bool
    let budget: Int64
    let budgetSpent: Int64
}

enum LedgerWidgetStore {
    static var directory: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LedgerAppGroup") as? String, !group.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    static var isAvailable: Bool { directory != nil }
    private static var file: URL? { directory?.appendingPathComponent("ledger-widget-v1.json") }
    static func read() -> LedgerWidgetSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(LedgerWidgetSnapshot.self, from: data)
    }
    static func write(_ snapshot: LedgerWidgetSnapshot) throws {
        guard let file else { return }
        try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear() throws {
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
