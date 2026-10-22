import Foundation

enum FinanceEvents {
    static let didChange = Notification.Name("ledger.financeDidChange")
    static func saved() { NotificationCenter.default.post(name: didChange, object: nil) }
}
