import AppIntents
import Foundation

@available(iOS 18.0, *)
enum LedgerControlDestination: String, AppEnum {
    case expense, income, dashboard, agenda
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tela do Ledger"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .expense: "Nova despesa", .income: "Nova receita", .dashboard: "Resumo", .agenda: "Agenda"
    ]
}

/// Included in both targets: the system dispatches OpenIntent to the containing app.
@available(iOS 18.0, *)
struct LedgerOpenControlIntent: OpenIntent {
    static var title: LocalizedStringResource = "Abrir Ledger"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false
    @Parameter(title: "Destino") var target: LedgerControlDestination
    init() { target = .dashboard }
    init(target: LedgerControlDestination) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        #if !LEDGER_WIDGET_EXTENSION
        if let url = URL(string: "ledger://\(target.rawValue)") { LedgerRouter.shared.open(url) }
        #endif
        return .result()
    }
}
