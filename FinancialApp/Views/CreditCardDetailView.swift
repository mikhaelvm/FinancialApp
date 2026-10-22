import SwiftUI
import SwiftData
import Charts

struct CreditCardDetailView: View {
    let card: CreditCard
    @Environment(\.modelContext) private var context
    @Query private var subscriptions: [Subscription]
    @State private var selectedDue: Date?
    @State private var showEdit = false
    @State private var showPurchase = false
    @State private var confirmPayment = false
    @State private var error: String?

    private var invoices: [Invoice] {
        let horizon = max(FinanceDate.date(day: 31, inMonth: FinanceDate.monthOffset(11, from: .now)),
                          card.transactions.compactMap(\.invoiceDueDate).max() ?? .now)
        return InvoiceEngine().invoices(for: card, subscriptions: subscriptions, through: horizon)
    }
    private func selectedInvoice(in invoices: [Invoice]) -> Invoice? {
        invoices.first { $0.dueDate == selectedDue }
            ?? invoices.first { $0.remainingCents > 0 && $0.dueDate >= FinanceDate.day(.now) }
            ?? invoices.last
    }

    var body: some View {
        let invoices = self.invoices
        let selected = selectedInvoice(in: invoices)
        let forecasts = (0..<12).map { offset in
            let month = FinanceDate.monthOffset(offset, from: .now)
            return MonthForecast(month: month, invoiceCents: invoices.filter { FinanceDate.sameMonth($0.dueDate, month) }.reduce(0) { $0 + $1.remainingCents })
        }
        List {
            Section("Limite") {
                CreditLimitSummary(card: card)
                if card.usedLimitCents > card.limitCents {
                    Label("Limite excedido por cobranças recorrentes", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                if invoices.isEmpty {
                    ContentUnavailableView("Nenhuma fatura", systemImage: "doc.text",
                                           description: Text("Adicione uma compra ou assinatura neste cartão."))
                } else {
                    Picker("Fatura por vencimento", selection: Binding(
                        get: { selected?.dueDate ?? Date.distantPast }, set: { selectedDue = $0 }
                    )) {
                        ForEach(invoices) { invoice in
                            Text("\(FinanceDate.monthTitle(invoice.dueDate)) • \(invoice.status())").tag(invoice.dueDate)
                        }
                    }
                    if let invoice = selected {
                        Text(invoice.status()).font(.headline)
                            .foregroundStyle(invoice.status() == "Vencida" ? .red : .secondary)
                        LabeledContent("Fechamento", value: invoice.closingDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Vencimento", value: invoice.dueDate.formatted(date: .abbreviated, time: .omitted))
                        MoneyRow(title: "Total com previsão", cents: invoice.totalCents)
                        MoneyRow(title: "Pago", cents: invoice.paidCents, symbol: "checkmark.circle")
                        MoneyRow(title: "Pendente", cents: invoice.remainingCents, symbol: "clock", tint: .orange)
                        if FinanceDate.day(.now) >= invoice.closingDate && invoice.payableCents > 0 {
                            Button("Registrar pagamento de \(Money.format(invoice.payableCents))", systemImage: "checkmark.seal") {
                                confirmPayment = true
                            }
                        }
                        ForEach(invoice.lines.sorted { $0.title < $1.title }) { line in
                            VStack(alignment: .leading, spacing: 6) {
                                MoneyRow(title: line.title, cents: line.amountCents,
                                         symbol: line.isProjected ? "clock.arrow.circlepath" : "bag")
                                CategoryLabel(category: line.category).font(.caption)
                                if line.totalInstallments > 1 {
                                    Text("Parcela \(line.installmentNumber)/\(line.totalInstallments)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ProgressView(value: Double(line.installmentNumber), total: Double(line.totalInstallments))
                                        .accessibilityLabel("Parcela \(line.installmentNumber) de \(line.totalInstallments)")
                                }
                                if line.isProjected {
                                    Text("Previsão de assinatura • ainda não lançada").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: { Text("Faturas abertas, fechadas e futuras") } footer: {
                Text("Registrar pagamento representa uma saída da conta e libera o limite. O app não movimenta dinheiro no banco.")
            }
            Section {
                InvoiceForecastChart(forecasts: forecasts)
                ForEach(forecasts) { item in MonthAmountRow(month: item.month, cents: item.invoiceCents) }
            } header: { Text("Próximas faturas") } footer: {
                Text("Valores pendentes por mês de vencimento, incluindo assinaturas previstas.")
            }
            if !card.transactions.isEmpty {
                Section {
                    DisclosureGroup("Limite comprometido por mês") {
                        ForEach(forecasts) { item in
                            let committed = card.transactions.filter { ($0.invoiceDueDate ?? .distantPast) >= item.month }.reduce(Int64(0)) { $0 + $1.amountCents }
                            let paid = card.payments.filter { $0.invoiceDueDate >= item.month }.reduce(Int64(0)) { $0 + $1.amountCents }
                            MonthAmountRow(month: item.month, cents: max(0, committed - paid))
                        }
                    }
                } footer: {
                    Text("Compras já lançadas a quitar a partir de cada mês, supondo a quitação das faturas anteriores.")
                }
            }
        }
        .ledgerListScreen(card.name, largeTitle: false)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                LedgerToolbarButton("Editar cartão", systemImage: "pencil") { showEdit = true }
                LedgerToolbarButton("Adicionar compra", systemImage: "plus") { showPurchase = true }
            }
        }
        .sheet(isPresented: $showEdit) { CardFormView(card: card) }
        .sheet(isPresented: $showPurchase) { AddTransactionView(initialCard: card) }
        .confirmationDialog("Confirmar pagamento da fatura?", isPresented: $confirmPayment, titleVisibility: .visible) {
            Button("Registrar pagamento") {
                guard let selected else { return }
                do { try CreditCardViewModel().pay(context: context, card: card, invoice: selected) }
                catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("O valor será descontado do saldo consolidado. Confirme somente se o pagamento já foi feito.")
        }
        .financeError($error)
    }
}

private struct CreditLimitSummary: View {
    let card: CreditCard
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Disponível para compras").font(.subheadline).foregroundStyle(.secondary)
                Text(display(card.availableLimitCents))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    .minimumScaleFactor(0.65).lineLimit(1)
            }
            if !hideAmounts {
                ProgressView(value: min(Double(card.usedLimitCents), Double(card.limitCents)), total: Double(max(1, card.limitCents)))
                    .tint(card.usedLimitCents >= card.limitCents ? .orange : LedgerTheme.accent)
                    .accessibilityLabel("Limite utilizado").accessibilityValue(Money.format(card.usedLimitCents))
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                metric("Limite total", cents: card.limitCents)
                metric("Em uso", cents: card.usedLimitCents)
            }
            Divider()
            Text("Fecha dia \(card.closingDay) • Vence dia \(card.dueDay)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
    private func display(_ cents: Int64) -> String { hideAmounts ? "••••" : Money.format(cents) }
    private func metric(_ title: String, cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(display(cents)).font(.subheadline.weight(.medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
