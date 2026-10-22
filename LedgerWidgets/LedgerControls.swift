import AppIntents
import WidgetKit
import SwiftUI

@available(iOS 18.0, *)
struct LedgerExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Ledger.Control.Expense") {
            ControlWidgetButton(action: LedgerOpenControlIntent(target: .expense)) { Label("Nova despesa", systemImage: "minus.circle") }
        }.displayName("Nova despesa").description("Abra o lançamento de uma despesa no Ledger.")
    }
}
@available(iOS 18.0, *)
struct LedgerIncomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Ledger.Control.Income") {
            ControlWidgetButton(action: LedgerOpenControlIntent(target: .income)) { Label("Nova receita", systemImage: "plus.circle") }
        }.displayName("Nova receita").description("Abra o lançamento de uma receita no Ledger.")
    }
}
@available(iOS 18.0, *)
struct LedgerDashboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Ledger.Control.Dashboard") {
            ControlWidgetButton(action: LedgerOpenControlIntent(target: .dashboard)) { Label("Resumo", systemImage: "chart.pie") }
        }.displayName("Resumo financeiro").description("Consulte o resumo do Ledger.")
    }
}
@available(iOS 18.0, *)
struct LedgerAgendaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Ledger.Control.Agenda") {
            ControlWidgetButton(action: LedgerOpenControlIntent(target: .agenda)) { Label("Agenda", systemImage: "calendar") }
        }.displayName("Pagamentos").description("Consulte a Agenda de pagamentos do Ledger.")
    }
}
