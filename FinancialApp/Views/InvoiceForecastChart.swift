import SwiftUI
import Charts

struct MonthAmountRow: View {
    let month: Date
    let cents: Int64
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(FinanceDate.monthTitle(month)).foregroundStyle(Color.primary)
                Spacer(minLength: 12)
                amount
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(FinanceDate.monthTitle(month)).foregroundStyle(Color.primary)
                amount
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
    private var amount: some View {
        Text(hideAmounts ? "••••" : Money.format(cents)).monospacedDigit().foregroundStyle(Color.primary)
    }
}

struct InvoiceForecastChart: View {
    let forecasts: [MonthForecast]
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    var body: some View {
        if hideAmounts {
            Label("Valores ocultos", systemImage: "eye.slash").font(.footnote).foregroundStyle(.secondary)
        } else if forecasts.allSatisfy({ $0.invoiceCents == 0 }) {
            Text("Nenhuma fatura prevista neste período.").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8)
        } else {
            Chart(forecasts) { item in
                BarMark(x: .value("Mês", item.month, unit: .month), y: .value("R$", Double(item.invoiceCents) / 100))
                    .foregroundStyle(LedgerTheme.accent).cornerRadius(3)
                    .accessibilityLabel(FinanceDate.monthTitle(item.month)).accessibilityValue(Money.format(item.invoiceCents))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            VStack(spacing: 2) {
                                Text(FinanceDate.shortMonthTitle(date))
                                Text(date, format: .dateTime.year()).font(.caption2)
                            }
                        }
                    }
                }
            }
            .frame(height: 180).padding(.vertical, 8)
        }
    }
}
