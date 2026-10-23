import Foundation

enum FinanceEvents {
    static let didChange = Notification.Name("trackr.financeDidChange")
    static func saved() { NotificationCenter.default.post(name: didChange, object: nil) }
}
