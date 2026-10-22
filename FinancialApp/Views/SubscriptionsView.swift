import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.nextRenewalDate) private var subscriptions: [Subscription]
    @State private var viewModel = SubscriptionViewModel()
    @State private var showAdd = false
    @State private var editing: Subscription?
    @State private var deleting: Subscription?
    @State private var error: String?
    @State private var showActive = true
    @State private var search = ""

    private var monthlyCents: Int64 {
        Int64(subscriptions.filter(\.isActive).reduce(0.0) { $0 + $1.monthlyEquivalentCents }.rounded())
    }
    private func isSoon(_ subscription: Subscription) -> Bool {
        guard subscription.isActive else { return false }
        let end = FinanceDate.calendar.date(byAdding: .day, value: 7, to: FinanceDate.day(.now))!
        return subscription.nextRenewalDate >= FinanceDate.day(.now) && subscription.nextRenewalDate <= end
    }

    var body: some View {
        List {
            Section {
                LedgerSummaryHeader(eyebrow: "Seu compromisso mensal fixo", title: Money.format(monthlyCents),
                                    subtitle: "\(subscriptions.filter(\.isActive).count) recorrências ativas • média mensal", symbol: "repeat")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                Picker("Situação", selection: $showActive) {
                    Text("Ativas").tag(true)
                    Text("Pausadas").tag(false)
                }.pickerStyle(.segmented)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if subscriptions.isEmpty {
                ContentUnavailableView("Suas assinaturas", systemImage: "repeat.circle",
                                       description: Text("Acompanhe serviços e despesas recorrentes em um só lugar."))
            }
            if subscriptions.contains(where: isSoon) {
                Section("Renovam nos próximos 7 dias") {
                    ForEach(subscriptions.filter(isSoon)) { subscription in
                        Button { editing = subscription } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(subscription.title)
                                    Text("\(hideAmounts ? "••••" : Money.format(subscription.amountCents)) • \(subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                }
                            } icon: { Image(systemName: "bell.badge.fill").foregroundStyle(.orange) }
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section {
                ForEach(subscriptions.filter { $0.isActive == showActive && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { subscription in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editing = subscription } label: {
                            HStack(alignment: .top, spacing: 12) {
                                SymbolTile(symbol: subscription.category?.symbol ?? "repeat", tint: subscription.category?.color ?? LedgerTheme.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(subscription.title).font(.headline)
                                    CategoryLabel(category: subscription.category).font(.caption)
                                    Text(subscription.card?.name ?? "Débito / conta")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if subscription.isActive {
                                        Text("Próxima: \(subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(isSoon(subscription) ? .orange : .secondary)
                                    }
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(hideAmounts ? "••••" : Money.format(subscription.amountCents)).font(.subheadline.bold()).monospacedDigit()
                                    Text(subscription.cycle.title.lowercased()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        Toggle("Registrar próximas cobranças", isOn: Binding(get: { subscription.isActive }, set: { active in
                            do { try viewModel.setActive(active, subscription: subscription, context: context) }
                            catch { self.error = error.localizedDescription }
                        })).font(.caption)
                    }
                    .swipeActions {
                        Button("Excluir", role: .destructive) { deleting = subscription }.tint(.red)
                        Button("Editar") { editing = subscription }.tint(.blue)
                    }
                }
            } header: { Text(showActive ? "Serviços e contas recorrentes" : "Recorrências pausadas") } footer: {
                Text("Média: mensal = valor; anual ÷ 12; semanal × 52 ÷ 12. Pausar no Ledger interrompe os lançamentos futuros e os alertas; não cancela sua contratação com o serviço.")
            }
        }
        .ledgerListScreen("Recorrentes")
        .searchable(text: $search, prompt: "Buscar serviço ou conta")
        .toolbar { LedgerToolbarButton("Adicionar assinatura", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { AddTransactionView(initialMode: .subscription) }
        .sheet(item: $editing) { AddTransactionView(subscription: $0) }
        .confirmationDialog("Excluir assinatura?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                guard let deleting else { return }
                do { try viewModel.delete(deleting, context: context) }
                catch { self.error = error.localizedDescription }
                self.deleting = nil
            }
        } message: { Text("Cobranças já lançadas serão preservadas no histórico.") }
        .financeError($error)
    }
}
