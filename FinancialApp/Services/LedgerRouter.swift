import Foundation
import Observation

enum LedgerTab: String, CaseIterable {
    case dashboard, transactions, cards, subscriptions, agenda
}

@MainActor @Observable
final class LedgerRouter {
    static let shared = LedgerRouter()
    var selectedTab: LedgerTab = .dashboard
    var cardPath: [UUID] = []
    var searchTerm = ""
    var selectedTransactionID: UUID?
    var showNewExpense = false
    var showNewIncome = false

    func reset() {
        selectedTab = .dashboard; cardPath = []; searchTerm = ""; selectedTransactionID = nil
        showNewExpense = false; showNewIncome = false
    }

    func search(_ term: String) {
        searchTerm = term
        selectedTab = .transactions
    }

    func openReminder(kind: String, cardID: String? = nil) {
        if kind == "invoice", let cardID, let id = UUID(uuidString: cardID) {
            cardPath = [id]
            selectedTab = .cards
        } else if kind == "subscription" {
            selectedTab = .subscriptions
        } else {
            selectedTab = .agenda
        }
    }

    func open(_ url: URL) {
        guard url.scheme == "ledger" else { return }
        switch url.host {
        case "expense": showNewExpense = true
        case "income": showNewIncome = true
        case "agenda": selectedTab = .agenda
        case "subscriptions": selectedTab = .subscriptions
        case "cards": selectedTab = .cards
        case "search":
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "q" })?.value ?? ""
            search(term)
        default: selectedTab = .dashboard
        }
    }
}
