import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.nextRenewalDate) private var subscriptions: [Subscription]
    @State private var viewModel = SubscriptionViewModel()
    @State private var showAdd = false
    @State private var editing: Subscription?
    @State private var deleting: Subscription?
    @State private var error: String?

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
                MoneyRow(title: "Compromisso mensal", cents: monthlyCents, symbol: "repeat", tint: .blue)
                Text("Semanais × 52 ÷ 12 e anuais ÷ 12. O valor efetivo de cada mês depende das datas de cobrança.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                                    Text("\(Money.format(subscription.amountCents)) • \(subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                }
                            } icon: { Image(systemName: "bell.badge.fill").foregroundStyle(.orange) }
                        }
                    }
                }
            }
            Section("Serviços e recorrências") {
                ForEach(subscriptions) { subscription in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editing = subscription } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                MoneyRow(title: subscription.title, cents: subscription.amountCents, symbol: "repeat")
                                CategoryLabel(category: subscription.category).font(.caption)
                                Text("\(subscription.cycle.title) • \(subscription.card?.name ?? "Débito / conta")")
                                    .font(.caption).foregroundStyle(.secondary)
                                if subscription.isActive {
                                    Text("Próxima: \(subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(isSoon(subscription) ? .orange : .secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        Toggle("Ativa", isOn: Binding(get: { subscription.isActive }, set: { active in
                            do { try viewModel.setActive(active, subscription: subscription, context: context) }
                            catch { self.error = error.localizedDescription }
                        }))
                    }
                    .swipeActions {
                        Button("Excluir", role: .destructive) { deleting = subscription }
                        Button("Editar") { editing = subscription }.tint(.blue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Assinaturas")
        .toolbar { Button("Adicionar assinatura", systemImage: "plus") { showAdd = true } }
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
