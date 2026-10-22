import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var transactions: [Transaction]
    @Query private var cards: [CreditCard]
    @Query private var subscriptions: [Subscription]
    @Query private var payments: [InvoicePayment]
    @State private var viewModel = DashboardViewModel()
    @State private var showAdd = false

    var body: some View {
        let snapshot = viewModel.snapshot(transactions: transactions, cards: cards,
                                          subscriptions: subscriptions, payments: payments, month: .now)
        List {
            Section("Saldo consolidado") {
                Text(Money.format(snapshot.balance))
                    .font(.largeTitle.bold()).minimumScaleFactor(0.6)
                    .foregroundStyle(snapshot.balance < 0 ? .red : .primary)
                    .accessibilityLabel("Saldo consolidado: \(Money.format(snapshot.balance))")
                Text("Saldo inicial zero + receitas − despesas à vista − pagamentos de faturas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                MoneyRow(title: "Entradas", cents: snapshot.income, symbol: "arrow.down.circle", tint: .green)
                MoneyRow(title: "Saídas à vista", cents: snapshot.cashExpenses, symbol: "arrow.up.circle", tint: .orange)
                MoneyRow(title: "Faturas pagas", cents: snapshot.payments, symbol: "checkmark.circle")
                MoneyRow(title: "Faturas pendentes", cents: snapshot.pendingInvoices, symbol: "creditcard", tint: .orange)
                MoneyRow(title: "Recorrências na conta a vencer", cents: snapshot.upcomingCash, symbol: "repeat")
                MoneyRow(title: "Saldo após compromissos", cents: snapshot.projectedBalance,
                         symbol: "calendar", tint: snapshot.projectedBalance < 0 ? .red : .green)
            } header: {
                Text(FinanceDate.monthTitle(.now))
            } footer: {
                Text("Pendentes incluem faturas vencidas e cobranças previstas até o fim do mês. Projeções não incluem receitas futuras nem compras ainda não registradas.")
            }
            Section {
                if snapshot.categories.isEmpty {
                    Text("Registre despesas para visualizar suas categorias.").foregroundStyle(.secondary)
                } else {
                    Chart(snapshot.categories) { item in
                        SectorMark(angle: .value("Valor", Double(item.cents) / 100), innerRadius: .ratio(0.6))
                            .foregroundStyle(by: .value("Categoria", item.name))
                            .accessibilityLabel(item.name).accessibilityValue(Money.format(item.cents))
                    }
                    .frame(height: 240)
                    ForEach(snapshot.categories) { item in
                        MoneyRow(title: item.name, cents: item.cents)
                    }
                }
            } header: {
                Text("Despesas por categoria")
            } footer: {
                Text("Despesas à vista do mês + parcelas e assinaturas nas faturas com vencimento no mês. Pagamentos de faturas não são contados novamente.")
            }
            Section("Faturas dos próximos 12 meses") {
                Chart(snapshot.forecasts) { item in
                    BarMark(x: .value("Mês", item.month, unit: .month),
                            y: .value("Pendente (R$)", Double(item.invoiceCents) / 100))
                        .foregroundStyle(.blue.gradient)
                        .accessibilityLabel(FinanceDate.monthTitle(item.month))
                        .accessibilityValue(Money.format(item.invoiceCents))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 220)
                ForEach(snapshot.forecasts) { item in
                    MoneyRow(title: FinanceDate.monthTitle(item.month), cents: item.invoiceCents)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Meu Fluxo")
        .toolbar { Button("Adicionar", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { AddTransactionView() }
    }
}
