import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Query private var transactions: [Transaction]
    @Query private var cards: [CreditCard]
    @Query private var subscriptions: [Subscription]
    @Query private var payments: [InvoicePayment]
    @State private var month = FinanceDate.month(.now)
    @State private var viewModel = DashboardViewModel()
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    var body: some View {
        let snapshot = viewModel.snapshot(transactions: transactions, cards: cards, subscriptions: subscriptions, payments: payments, month: month)
        List {
            Section {
                HStack {
                    Button("Mês anterior", systemImage: "chevron.left") { month = FinanceDate.monthOffset(-1, from: month) }.labelStyle(.iconOnly)
                    Spacer()
                    Text(FinanceDate.monthTitle(month).capitalized).font(.headline)
                    Spacer()
                    Button("Próximo mês", systemImage: "chevron.right") { month = FinanceDate.monthOffset(1, from: month) }.labelStyle(.iconOnly)
                }.buttonStyle(.borderless)
            }
            Section("Movimento da conta") {
                MoneyRow(title: "Receitas", cents: snapshot.income, symbol: "arrow.down.left", tint: .green)
                MoneyRow(title: "Despesas", cents: snapshot.cashExpenses, symbol: "arrow.up.right")
                MoneyRow(title: "Faturas pagas", cents: snapshot.payments, symbol: "creditcard")
                MoneyRow(title: "Resultado na conta", cents: snapshot.income - snapshot.cashExpenses - snapshot.payments, symbol: "equal.circle")
            }
            Section {
                if !hideAmounts && !snapshot.categories.isEmpty {
                    Chart(Array(snapshot.categories.prefix(8))) { item in
                        BarMark(x: .value("R$", Double(item.cents) / 100), y: .value("Categoria", item.name))
                            .foregroundStyle(item.color)
                    }.frame(height: CGFloat(max(160, min(8, snapshot.categories.count) * 38)))
                }
                ForEach(snapshot.categories) { item in CategoryExpenseRow(item: item) }
                if snapshot.categories.isEmpty { Text("Sem despesas neste mês").foregroundStyle(.secondary) }
            } header: { Text("Despesas por categoria") } footer: {
                Text("Gastos na conta e parcelas por vencimento. Para meses futuros, valores de assinaturas são previsões. O resultado da conta usa apenas movimentos realizados.")
            }
            NavigationLink { DataManagementView() } label: { Label("Exportar dados", systemImage: "square.and.arrow.up") }
        }.listStyle(.insetGrouped).navigationTitle("Relatórios").navigationBarTitleDisplayMode(.inline)
    }
}
