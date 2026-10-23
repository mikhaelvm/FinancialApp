import SwiftUI

struct BudgetProgressView: View {
    let spentCents: Int64
    let budgetCents: Int64
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Orçamento mensal", systemImage: "chart.pie").font(.subheadline.weight(.medium))
            if budgetCents > 0 {
                if !hideAmounts {
                    Text("\(Money.format(spentCents)) de \(Money.format(budgetCents))")
                        .font(.caption).foregroundStyle(spentCents > budgetCents ? .orange : .secondary)
                    ProgressView(value: min(Double(spentCents), Double(budgetCents)), total: Double(budgetCents))
                        .tint(spentCents > budgetCents ? .orange : TrackrTheme.accent)
                }
                Text(spentCents > budgetCents ? "Orçamento ultrapassado" : "Dentro do planejado")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Defina quanto pretende gastar por mês").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}

struct BudgetSettingsView: View {
    @AppStorage("trackr.monthlyBudgetCents") private var budget = 0.0
    @AppStorage("trackr.reserveGoalCents") private var goal = 0.0
    @State private var budgetText = ""
    @State private var goalText = ""
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Form {
            Section {
                CurrencyTextField(placeholder: "Orçamento em reais", text: $budgetText)
            } header: { Text("Limite de gastos do mês") } footer: {
                Text("Considera gastos na conta e parcelas com vencimento no mês, incluindo previsões de assinaturas. Não soma pagamentos de faturas novamente. Deixe vazio para desativar.")
            }
            Section {
                CurrencyTextField(placeholder: "Meta em reais", text: $goalText)
            } header: { Text("Meta de reserva") } footer: {
                Text("Acompanha seu saldo consolidado em relação ao valor desejado. Definir uma meta não transfere dinheiro. Deixe vazio para desativar.")
            }
            Button("Salvar planejamento") {
                guard (budgetText.isEmpty || Money.parse(budgetText) != nil), (goalText.isEmpty || Money.parse(goalText) != nil) else {
                    error = "Use valores como 2.500,00, ou deixe vazio para desativar."; return
                }
                budget = Double(Money.parse(budgetText) ?? 0)
                goal = Double(Money.parse(goalText) ?? 0)
                saved = true
                FinanceEvents.saved()
            }
            if saved { Label("Planejamento salvo", systemImage: "checkmark.circle").foregroundStyle(.green) }
        }
        .trackrFormScreen("Planejamento")
        .onAppear {
            budgetText = budget > 0 ? Money.input(Int64(budget)) : ""
            goalText = goal > 0 ? Money.input(Int64(goal)) : ""
        }
        .financeError($error)
    }
}
