import Foundation
import Observation

enum LedgerTab: String, CaseIterable {
    case dashboard, transactions, cards, agenda
}

enum PaymentsSection: String, CaseIterable, Identifiable {
    case calendar = "Agenda", recurring = "Recorrentes"
    var id: String { rawValue }
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
    var paymentsSection = PaymentsSection.calendar

    func openPayments(_ section: PaymentsSection = .calendar) {
        paymentsSection = section; selectedTab = .agenda
    }

    func reset() {
        selectedTab = .dashboard; cardPath = []; searchTerm = ""; selectedTransactionID = nil
        showNewExpense = false; showNewIncome = false
        paymentsSection = .calendar
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
            openPayments(.recurring)
        } else {
            openPayments()
        }
    }

    func open(_ url: URL) {
        guard url.scheme == "ledger" else { return }
        switch url.host {
        case "expense": showNewExpense = true
        case "income": showNewIncome = true
        case "agenda": openPayments()
        case "subscriptions": openPayments(.recurring)
        case "cards": selectedTab = .cards
        case "search":
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "q" })?.value ?? ""
            search(term)
        default: selectedTab = .dashboard
        }
    }
}
