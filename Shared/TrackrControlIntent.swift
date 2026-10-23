import AppIntents
import Foundation

@available(iOS 18.0, *)
enum TrackrControlDestination: String, AppEnum {
    case expense, income, dashboard, agenda
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tela do Trackr"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .expense: "Nova despesa", .income: "Nova receita", .dashboard: "Resumo", .agenda: "Agenda"
    ]
}

/// Included in both targets: the system dispatches OpenIntent to the containing app.
@available(iOS 18.0, *)
struct TrackrOpenControlIntent: OpenIntent {
    static var title: LocalizedStringResource = "Abrir Trackr"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false
    @Parameter(title: "Destino") var target: TrackrControlDestination
    init() { target = .dashboard }
    init(target: TrackrControlDestination) { self.target = target }
    @MainActor func perform() async throws -> some IntentResult {
        #if !TRACKR_WIDGET_EXTENSION
        if let url = URL(string: "trackr://\(target.rawValue)") { TrackrRouter.shared.open(url) }
        #endif
        return .result()
    }
}
