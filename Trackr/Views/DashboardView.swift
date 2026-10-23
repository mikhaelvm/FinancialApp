import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var transactions: [Transaction]
    @Query private var cards: [CreditCard]
    @Query private var subscriptions: [Subscription]
    @Query private var payments: [InvoicePayment]
    @Query private var scheduled: [ScheduledPayment]
    @Environment(TrackrRouter.self) private var router
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    @AppStorage("trackr.monthlyBudgetCents") private var budget = 0.0
    @AppStorage("trackr.reserveGoalCents") private var reserveGoal = 0.0
    @AppStorage("trackr.dismissedPayments") private var dismissedPayments = ""
    @State private var viewModel = DashboardViewModel()
    @State private var entry: DashboardEntry?
    @State private var showSettings = false
    @State private var showForecast = false
    @State private var selectedPurchase: CardPurchaseGroup?

    private var upcoming: [PaymentCommitment] {
        let end = FinanceDate.calendar.date(byAdding: .day, value: 7, to: FinanceDate.day(.now))!
        return PaymentPlanner().commitments(cards: cards, subscriptions: subscriptions, scheduled: scheduled, through: end)
    }

    var body: some View {
        let snapshot = viewModel.snapshot(transactions: transactions, cards: cards, subscriptions: subscriptions,
                                          payments: payments, month: .now, scheduled: scheduled,
                                          dismissedIDs: Set(dismissedPayments.split(separator: "\n").map(String.init)))
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saldo na conta").font(.subheadline).foregroundStyle(.secondary)
                    Text(hideAmounts ? "••••" : Money.format(snapshot.balance))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    Label("Após os compromissos: \(hideAmounts ? "••••" : Money.format(snapshot.projectedBalance))",
                          systemImage: snapshot.projectedBalance < 0 ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.footnote).foregroundStyle(snapshot.projectedBalance < 0 ? .orange : .secondary)
                }.padding(.vertical, 12)
                TrackrDashboardActions(expense: { entry = .expense }, income: { entry = .income }, schedule: { entry = .scheduled })
            }
            Section(FinanceDate.monthTitle(.now).capitalized) {
                MoneyRow(title: "Receitas", cents: snapshot.income, symbol: "arrow.down.left.circle", tint: .green)
                MoneyRow(title: "Despesas na conta", cents: snapshot.cashExpenses, symbol: "arrow.up.right.circle")
                MoneyRow(title: "Faturas pagas", cents: snapshot.payments, symbol: "checkmark.circle")
                DisclosureGroup("Compromissos restantes") {
                    MoneyRow(title: "Faturas", cents: snapshot.pendingInvoices, symbol: "creditcard")
                    MoneyRow(title: "Recorrências na conta", cents: snapshot.upcomingCash, symbol: "repeat")
                    MoneyRow(title: "Contas agendadas", cents: snapshot.scheduledCents, symbol: "calendar")
                }
            }
            Section("Planejamento") {
                NavigationLink { CashFlowReviewView() } label: {
                    Label("Evolução da conta", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink { BudgetSettingsView() } label: {
                    Label("Orçamento mensal", systemImage: "chart.pie")
                }
                if reserveGoal > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Meta de reserva", systemImage: "target").font(.subheadline.weight(.medium))
                        if !hideAmounts {
                            Text("\(Money.format(max(0, snapshot.balance))) de \(Money.format(Int64(reserveGoal)))")
                                .font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: min(Double(max(0, snapshot.balance)), reserveGoal), total: reserveGoal)
                        }
                    }.padding(.vertical, 4)
                }
                NavigationLink { ReportsView() } label: { Label("Relatórios por mês", systemImage: "chart.bar.xaxis") }
            }
            Section {
                if upcoming.isEmpty {
                    Label("Nenhum compromisso nos próximos 7 dias", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(upcoming.prefix(3))) { item in
                    Button { router.openReminder(kind: item.kind.rawValue, cardID: item.sourceID.uuidString) } label: {
                        PaymentCommitmentRow(item: item)
                    }.buttonStyle(.plain)
                }
                Button("Ver todos os pagamentos") { router.openPayments() }
            } header: { Text("Próximos pagamentos") }
            if !CardPurchaseService.groups(for: cards).isEmpty {
                Section {
                    ForEach(Array(CardPurchaseService.groups(for: cards).prefix(3))) { purchase in
                        Button { selectedPurchase = purchase } label: { CardPurchaseRow(purchase: purchase) }.buttonStyle(.plain)
                    }
                } header: { Text("Últimas compras no cartão") } footer: {
                    Text("Compras e parcelas também aparecem no Extrato. O saldo da conta muda somente ao pagar a fatura.")
                }
            }
            Section("Despesas por categoria") {
                if snapshot.categories.isEmpty {
                    Text("Adicione uma despesa para conhecer seus hábitos.").foregroundStyle(.secondary)
                } else if hideAmounts {
                    Label("Valores e gráficos ocultos", systemImage: "eye.slash").foregroundStyle(.secondary)
                } else {
                    Chart(snapshot.categories) { item in
                        SectorMark(angle: .value("Valor", Double(item.cents) / 100), innerRadius: .ratio(0.7), angularInset: 2)
                            .foregroundStyle(by: .value("Categoria", item.name))
                            .accessibilityLabel(item.name).accessibilityValue(Money.format(item.cents))
                    }
                    .chartForegroundStyleScale(domain: snapshot.categories.map(\.name), range: snapshot.categories.map(\.color))
                    .frame(height: 200).padding(.vertical, 8)
                    ForEach(snapshot.categories) { item in CategoryExpenseRow(item: item) }
                }
            }
            Section {
                Button { showForecast.toggle() } label: {
                    HStack {
                        Text("Faturas dos próximos 12 meses").foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: showForecast ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if showForecast {
                    InvoiceForecastChart(forecasts: snapshot.forecasts)
                    ForEach(snapshot.forecasts) { item in MonthAmountRow(month: item.month, cents: item.invoiceCents) }
                }
            } footer: {
                Text("O saldo muda quando o dinheiro entra ou sai da conta. Compras no cartão entram nas faturas. Previsões incluem compromissos registrados, sem presumir receitas futuras.")
            }
        }
        .trackrListScreen("Resumo")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                TrackrToolbarButton("Ajustes", systemImage: "gearshape") { showSettings = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                TrackrToolbarButton(hideAmounts ? "Mostrar valores" : "Ocultar valores", systemImage: hideAmounts ? "eye.slash" : "eye") { hideAmounts.toggle() }
                Menu {
                    Button("Despesa", systemImage: "minus.circle") { entry = .expense }
                    Button("Receita", systemImage: "plus.circle") { entry = .income }
                    Button("Conta agendada", systemImage: "calendar.badge.plus") { entry = .scheduled }
                    Button("Recorrência", systemImage: "repeat") { entry = .recurring }
                } label: { Label("Novo lançamento", systemImage: "plus").labelStyle(.iconOnly) }
            }
        }
        .sheet(item: $entry) { action in AddTransactionView(initialMode: action.mode, initialKind: action.kind) }
        .sheet(isPresented: $showSettings) { NavigationStack { TrackrSettingsView() } }
        .sheet(item: $selectedPurchase) { CardPurchaseDetailView(card: $0.card, purchaseID: $0.purchaseID) }
        .onChange(of: hideAmounts) { _, _ in WidgetSnapshotService.refresh(context: context) }
    }
}

private enum DashboardEntry: String, Identifiable {
    case expense, income, scheduled, recurring
    var id: String { rawValue }
    var mode: EntryMode { self == .scheduled ? .scheduled : (self == .recurring ? .subscription : .single) }
    var kind: TransactionKind { self == .income ? .income : .expense }
}
