import SwiftUI
import SwiftData
import Charts

struct CashFlowReviewView: View {
    @Query private var transactions: [Transaction]
    @Query private var payments: [InvoicePayment]
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    var body: some View {
        let months = FinancialReview.months(transactions: transactions, payments: payments)
        List {
            Section {
                if hideAmounts {
                    Label("Valores e gráfico ocultos", systemImage: "eye.slash").foregroundStyle(.secondary)
                } else {
                    Chart(months) { month in
                        BarMark(x: .value("Mês", month.month, unit: .month), y: .value("R$", Double(month.income) / 100))
                            .foregroundStyle(by: .value("Movimento", "Entradas")).position(by: .value("Movimento", "Entradas"))
                            .accessibilityLabel("Entradas de \(FinanceDate.monthTitle(month.month))").accessibilityValue(Money.format(month.income))
                        BarMark(x: .value("Mês", month.month, unit: .month), y: .value("R$", Double(month.expenses) / 100))
                            .foregroundStyle(by: .value("Movimento", "Saídas")).position(by: .value("Movimento", "Saídas"))
                            .accessibilityLabel("Saídas de \(FinanceDate.monthTitle(month.month))").accessibilityValue(Money.format(month.expenses))
                    }
                    .chartForegroundStyleScale(["Entradas": LedgerTheme.income, "Saídas": LedgerTheme.expense])
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 220).padding(.vertical, 8)
                }
            } header: { Text("Últimos seis meses") } footer: {
                Text("Valores registrados na conta. Saídas incluem despesas à vista e pagamentos de faturas, sem somar novamente as compras no cartão. O mês atual está em andamento; o gráfico não presume saldo ou histórico anteriores ao Ledger.")
            }
            ForEach(months.reversed()) { month in
                Section(FinanceDate.monthTitle(month.month).capitalized) {
                    MoneyRow(title: "Entradas", cents: month.income, symbol: "arrow.down.left", tint: LedgerTheme.income)
                    MoneyRow(title: "Saídas realizadas", cents: month.expenses, symbol: "arrow.up.right")
                    MoneyRow(title: "Resultado do mês", cents: month.net, symbol: "equal.circle", tint: month.net < 0 ? .orange : .primary)
                }
            }
        }.ledgerListScreen("Evolução da conta", largeTitle: false)
    }
}

struct SpendingComparisonRow: View {
    let comparison: SpendingComparison
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    var body: some View {
        HStack(alignment: .top, spacing: LedgerTheme.rowSpacing) {
            SymbolTile(symbol: "chart.line.uptrend.xyaxis")
            VStack(alignment: .leading, spacing: 5) {
                Text("Saídas até o dia \(comparison.day)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                if hideAmounts { Text("Valores ocultos").font(.caption).foregroundStyle(.secondary) }
                else if let percent = comparison.percentChange {
                    Text("\(abs(percent).formatted(.number.precision(.fractionLength(0))))% \(percent > 0 ? "a mais" : (percent < 0 ? "a menos" : "de variação")) em relação ao mesmo período do mês anterior")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Ainda não há saídas registradas no período anterior para comparar.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }
}
