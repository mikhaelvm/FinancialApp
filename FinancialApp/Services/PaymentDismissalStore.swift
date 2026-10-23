import Foundation

/// A dismissal is an agenda preference, never a financial transaction.
enum PaymentDismissalStore {
    static func invoiceID(cardID: UUID, dueDate: Date) -> String {
        "invoice:\(cardID):\(FinanceDate.month(dueDate).timeIntervalSince1970)"
    }
    static let key = "ledger.dismissedPayments"
    static func ids(defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: key) ?? "").split(separator: "\n").map(String.init))
    }
    static func set(_ id: String, dismissed: Bool, defaults: UserDefaults = .standard) {
        var values = ids(defaults: defaults)
        if dismissed { values.insert(id) } else { values.remove(id) }
        defaults.set(values.sorted().joined(separator: "\n"), forKey: key)
        FinanceEvents.saved()
    }
    static func merge(_ incoming: [String]) {
        let values = ids().union(incoming)
        UserDefaults.standard.set(values.sorted().joined(separator: "\n"), forKey: key)
    }
}
