import AppIntents
import WidgetKit
import SwiftUI

@available(iOS 18.0, *)
struct TrackrExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Trackr.Control.Expense") {
            ControlWidgetButton(action: TrackrOpenControlIntent(target: .expense)) { Label("Nova despesa", systemImage: "minus.circle") }
        }.displayName("Nova despesa").description("Abra o lançamento de uma despesa no Trackr.")
    }
}
@available(iOS 18.0, *)
struct TrackrIncomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Trackr.Control.Income") {
            ControlWidgetButton(action: TrackrOpenControlIntent(target: .income)) { Label("Nova receita", systemImage: "plus.circle") }
        }.displayName("Nova receita").description("Abra o lançamento de uma receita no Trackr.")
    }
}
@available(iOS 18.0, *)
struct TrackrDashboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Trackr.Control.Dashboard") {
            ControlWidgetButton(action: TrackrOpenControlIntent(target: .dashboard)) { Label("Resumo", systemImage: "chart.pie") }
        }.displayName("Resumo financeiro").description("Consulte o resumo do Trackr.")
    }
}
@available(iOS 18.0, *)
struct TrackrAgendaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Trackr.Control.Agenda") {
            ControlWidgetButton(action: TrackrOpenControlIntent(target: .agenda)) { Label("Agenda", systemImage: "calendar") }
        }.displayName("Pagamentos").description("Consulte a Agenda de pagamentos do Trackr.")
    }
}
