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
        List {
            Section("Limite") {
                LedgerSummaryHeader(eyebrow: card.name, title: Money.format(card.availableLimitCents),
                                    subtitle: "disponíveis de \(Money.format(card.limitCents))", symbol: "creditcard.fill")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                MoneyRow(title: "Total", cents: card.limitCents, symbol: "creditcard")
                MoneyRow(title: "Comprometido", cents: card.usedLimitCents, symbol: "lock", tint: .orange)
                MoneyRow(title: "Disponível", cents: card.availableLimitCents, symbol: "checkmark.circle", tint: .green)
                ProgressView(value: min(Double(card.usedLimitCents), Double(card.limitCents)),
                             total: Double(max(1, card.limitCents)))
                    .accessibilityLabel("Limite comprometido")
                    .accessibilityValue(Money.format(card.usedLimitCents))
                if card.usedLimitCents > card.limitCents {
                    Label("Limite excedido por cobranças recorrentes", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Text("Fecha dia \(card.closingDay) • Vence dia \(card.dueDay)")
                    .font(.caption).foregroundStyle(.secondary)
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
                Chart(0..<12, id: \.self) { offset in
                    let month = FinanceDate.monthOffset(offset, from: .now)
                    let cents = invoices.filter { FinanceDate.sameMonth($0.dueDate, month) }
                        .reduce(Int64(0)) { $0 + $1.remainingCents }
                    BarMark(x: .value("Mês", month, unit: .month), y: .value("R$", Double(cents) / 100))
                        .foregroundStyle(.blue.gradient)
                        .accessibilityLabel(FinanceDate.monthTitle(month))
                        .accessibilityValue(Money.format(cents))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 200)
                ForEach(0..<12, id: \.self) { offset in
                    let month = FinanceDate.monthOffset(offset, from: .now)
                    let due = invoices.filter { FinanceDate.sameMonth($0.dueDate, month) }.reduce(Int64(0)) { $0 + $1.remainingCents }
                    let committed = card.transactions.filter { ($0.invoiceDueDate ?? .distantPast) >= month }
                        .reduce(Int64(0)) { $0 + $1.amountCents }
                    let paid = card.payments.filter { $0.invoiceDueDate >= month }.reduce(Int64(0)) { $0 + $1.amountCents }
                    VStack(alignment: .leading, spacing: 4) {
                        MoneyRow(title: FinanceDate.monthTitle(month), cents: due, symbol: "calendar")
                        Text("Parcelas e compras já lançadas a quitar a partir deste mês: \(Money.format(max(0, committed - paid)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Compromissos mês a mês") } footer: {
                Text("Barras incluem assinaturas previstas. O comprometimento acumulado considera somente compras já lançadas e supõe quitação das faturas anteriores.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(card.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Editar cartão", systemImage: "pencil") { showEdit = true }
                Button("Adicionar compra", systemImage: "plus") { showPurchase = true }
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
