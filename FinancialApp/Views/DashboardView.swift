import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var transactions: [Transaction]
    @Query private var cards: [CreditCard]
    @Query private var subscriptions: [Subscription]
    @Query private var payments: [InvoicePayment]
    @Query private var scheduled: [ScheduledPayment]
    @Environment(LedgerRouter.self) private var router
    @State private var viewModel = DashboardViewModel()
    @State private var entry: DashboardEntry?
    @State private var showSettings = false

    private var upcoming: [PaymentCommitment] {
        let end = FinanceDate.calendar.date(byAdding: .day, value: 7, to: FinanceDate.day(.now))!
        return PaymentPlanner().commitments(cards: cards, subscriptions: subscriptions, scheduled: scheduled, through: end)
    }

    var body: some View {
        let snapshot = viewModel.snapshot(transactions: transactions, cards: cards,
                                          subscriptions: subscriptions, payments: payments, month: .now, scheduled: scheduled)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image("LedgerMark").resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Seu dinheiro, com clareza.").font(.headline)
                        Text(FinanceDate.monthTitle(.now).capitalized).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                LedgerSummaryHeader(eyebrow: "Saldo disponível na conta", title: Money.format(snapshot.balance),
                                    subtitle: "Após os compromissos do mês: \(Money.format(snapshot.projectedBalance))", symbol: "wallet.bifold")
                quickActions
                monthOverview(snapshot)
                upcomingSection
                categoriesSection(snapshot)
                forecastSection(snapshot)
                Text("O saldo considera apenas o que já entrou ou saiu da conta. Compras no cartão são descontadas quando a fatura é paga.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Ledger")
        .toolbar { Button("Preferências e alertas", systemImage: "bell.badge") { showSettings = true } }
        .sheet(item: $entry) { action in AddTransactionView(initialMode: action.mode, initialKind: action.kind) }
        .sheet(isPresented: $showSettings) { NavigationStack { LedgerSettingsView() } }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            quickAction("Registrar gasto", symbol: "minus.circle.fill", tint: .orange, action: .expense)
            quickAction("Receber dinheiro", symbol: "plus.circle.fill", tint: LedgerTheme.accent, action: .income)
            quickAction("Agendar conta", symbol: "calendar.badge.plus", tint: .blue, action: .scheduled)
            quickAction("Nova recorrência", symbol: "repeat.circle.fill", tint: .purple, action: .recurring)
        }
    }

    private func quickAction(_ title: String, symbol: String, tint: Color, action: DashboardEntry) -> some View {
        Button { entry = action } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 56)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func monthOverview(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seu mês em um olhar").font(.title3.bold())
            MoneyRow(title: "Recebido", cents: snapshot.income, symbol: "arrow.down.left.circle.fill", tint: LedgerTheme.accent)
            MoneyRow(title: "Gastos na conta", cents: snapshot.cashExpenses, symbol: "arrow.up.right.circle.fill", tint: .orange)
            MoneyRow(title: "Faturas já pagas", cents: snapshot.payments, symbol: "checkmark.circle.fill")
            Divider()
            MoneyRow(title: "Faturas a pagar", cents: snapshot.pendingInvoices, symbol: "creditcard")
            MoneyRow(title: "Recorrências a debitar", cents: snapshot.upcomingCash, symbol: "repeat")
            MoneyRow(title: "Contas agendadas", cents: snapshot.scheduledCents, symbol: "calendar")
            HStack(alignment: .top) {
                Image(systemName: snapshot.projectedBalance < 0 ? "exclamationmark.circle.fill" : "checkmark.shield.fill")
                Text(snapshot.projectedBalance < 0
                     ? "Os compromissos superam seu saldo. Confira a Agenda e planeje as próximas entradas."
                     : "Você tem saldo para os compromissos registrados até o fim do mês.")
            }
            .font(.footnote).foregroundStyle(snapshot.projectedBalance < 0 ? .orange : LedgerTheme.accent)
        }.ledgerSurface()
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("No seu radar").font(.title3.bold())
                Spacer()
                Button("Ver agenda") { router.selectedTab = .agenda }.font(.subheadline.weight(.semibold))
            }
            if upcoming.isEmpty {
                Label("Nenhum compromisso nos próximos 7 dias.", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(upcoming.prefix(3))) { item in
                    Button { router.openReminder(kind: item.kind.rawValue, cardID: item.sourceID.uuidString) } label: {
                        PaymentCommitmentRow(item: item)
                    }.buttonStyle(.plain)
                }
            }
        }.ledgerSurface()
    }

    private func categoriesSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Para onde vai seu dinheiro").font(.title3.bold())
            if snapshot.categories.isEmpty {
                Label("Seus gastos por categoria aparecerão aqui.", systemImage: "chart.pie")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(snapshot.categories) { item in
                    SectorMark(angle: .value("Valor", Double(item.cents) / 100), innerRadius: .ratio(0.68), angularInset: 3)
                        .cornerRadius(5).foregroundStyle(by: .value("Categoria", item.name))
                        .accessibilityLabel(item.name).accessibilityValue(Money.format(item.cents))
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12).frame(height: 240)
                DisclosureGroup("Detalhar categorias") {
                    ForEach(snapshot.categories) { item in MoneyRow(title: item.name, cents: item.cents).padding(.vertical, 6) }
                }.font(.subheadline)
                Text("Gastos na conta e faturas com vencimento neste mês. Inclui previsões de assinaturas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.ledgerSurface()
    }

    private func forecastSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Olhe à frente").font(.title3.bold())
            Text("Faturas pendentes nos próximos 12 meses").font(.subheadline).foregroundStyle(.secondary)
            Chart(snapshot.forecasts) { item in
                BarMark(x: .value("Mês", item.month, unit: .month), y: .value("R$", Double(item.invoiceCents) / 100))
                    .cornerRadius(5).foregroundStyle(LedgerTheme.accent.gradient)
                    .accessibilityLabel(FinanceDate.monthTitle(item.month)).accessibilityValue(Money.format(item.invoiceCents))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 190)
            DisclosureGroup("Ver valores por mês") {
                ForEach(snapshot.forecasts) { item in
                    MoneyRow(title: FinanceDate.monthTitle(item.month), cents: item.invoiceCents).padding(.vertical, 6)
                }
            }.font(.subheadline)
        }.ledgerSurface()
    }
}

private enum DashboardEntry: String, Identifiable {
    case expense, income, scheduled, recurring
    var id: String { rawValue }
    var mode: EntryMode { self == .scheduled ? .scheduled : (self == .recurring ? .subscription : .single) }
    var kind: TransactionKind { self == .income ? .income : .expense }
}
