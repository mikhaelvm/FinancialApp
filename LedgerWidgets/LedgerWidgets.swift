import WidgetKit
import SwiftUI

private struct LedgerEntry: TimelineEntry {
    let date: Date
    let snapshot: LedgerWidgetSnapshot?
}

private struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry { preview }
    func getSnapshot(in context: Context, completion: @escaping (LedgerEntry) -> Void) {
        completion(context.isPreview ? preview : LedgerEntry(date: .now, snapshot: LedgerWidgetStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerEntry>) -> Void) {
        completion(Timeline(entries: [LedgerEntry(date: .now, snapshot: LedgerWidgetStore.read())], policy: .after(Date.now.addingTimeInterval(3600))))
    }
    private var preview: LedgerEntry {
        LedgerEntry(date: .now, snapshot: LedgerWidgetSnapshot(updatedAt: .now, month: .now, balance: 245_000,
            income: 500_000, expenses: 255_000, pendingInvoices: 84_000, projectedBalance: 161_000,
            upcoming: [LedgerWidgetPayment(id: "preview", title: "Conta de energia", date: .now, cents: 12_000)],
            hidesAmounts: false, budget: 300_000, budgetSpent: 255_000))
    }
}

private struct LedgerDashboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry
    var body: some View {
        Group {
            if entry.snapshot?.accessProtected == true {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ledger", systemImage: "lock.shield").font(.headline)
                    Text("Desbloqueie no app").font(.caption).foregroundStyle(.secondary)
                }
            } else if let snapshot = entry.snapshot {
                dashboard(snapshot)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ledger", systemImage: "chart.pie.fill").font(.headline)
                    Text("Abra o Ledger").font(.subheadline.weight(.semibold))
                    if family == .systemMedium || family == .systemLarge {
                        Text("Atualize o resumo no app. O compartilhamento depende do App Group autorizado na instalação.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        .widgetURL(URL(string: family == .accessoryRectangular || family == .accessoryCircular ? "ledger://agenda" : "ledger://dashboard"))
    }

    @ViewBuilder private func dashboard(_ snapshot: LedgerWidgetSnapshot) -> some View {
        if family == .accessoryCircular {
            VStack(spacing: 2) {
                Image(systemName: "calendar")
                Text("\(snapshot.upcoming.count)" + (snapshot.upcoming.count == 3 ? "+" : "")).font(.headline)
            }.accessibilityLabel("Próximos pagamentos: \(snapshot.upcoming.count) ou mais")
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Label("Próximo pagamento", systemImage: "calendar")
                if let next = snapshot.upcoming.first {
                    Text(next.title).lineLimit(1)
                    Text("\(next.date.formatted(.dateTime.day().month(.abbreviated))) · \(amount(next.cents, snapshot))").font(.caption).privacySensitive()
                } else { Text("Nenhum previsto").font(.caption) }
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
                HStack {
                    Label("Ledger", systemImage: "chart.pie.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot.month, format: .dateTime.month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                }
                Text("Saldo em conta").font(.caption).foregroundStyle(.secondary)
                Text(amount(snapshot.balance, snapshot)).font(.system(family == .systemSmall ? .title3 : .title2, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.6).lineLimit(1).privacySensitive()
                if family != .systemSmall {
                    HStack(alignment: .top, spacing: 12) {
                        metric("Entradas", cents: snapshot.income, snapshot: snapshot)
                        metric("Saídas pagas", cents: snapshot.expenses, snapshot: snapshot)
                        metric("Faturas a pagar", cents: snapshot.pendingInvoices, snapshot: snapshot)
                    }
                } else {
                    Text("A pagar em faturas").font(.caption2).foregroundStyle(.secondary)
                    Text(amount(snapshot.pendingInvoices, snapshot)).font(.subheadline).privacySensitive()
                }
                if family == .systemLarge {
                    Divider()
                    if snapshot.budget > 0 {
                        HStack { Text("Orçamento do mês"); Spacer(); Text(amount(snapshot.budget, snapshot)).privacySensitive() }.font(.caption)
                        ProgressView(value: min(Double(snapshot.budgetSpent) / Double(snapshot.budget), 1)).tint(.teal)
                            .redacted(reason: snapshot.hidesAmounts ? .placeholder : []).privacySensitive()
                    }
                    Text("Próximos pagamentos").font(.caption.weight(.semibold))
                    if snapshot.upcoming.isEmpty { Text("Nenhum previsto").font(.caption).foregroundStyle(.secondary) }
                    ForEach(snapshot.upcoming) { payment in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(payment.title).lineLimit(1)
                                Text(payment.date, format: .dateTime.day().month(.abbreviated)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(amount(payment.cents, snapshot)).privacySensitive()
                        }.font(.caption)
                    }
                }
                Spacer(minLength: 0)
                Text("Atualizado \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private func amount(_ cents: Int64, _ snapshot: LedgerWidgetSnapshot) -> String {
        snapshot.hidesAmounts ? "••••" : (Double(cents) / 100).formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }
    private func metric(_ title: String, cents: Int64, snapshot: LedgerWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(amount(cents, snapshot)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6).privacySensitive()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LedgerDashboardWidget: Widget {
    // Preserve the previous kind so installed widgets upgrade in place.
    let kind = "LedgerQuickActions"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerProvider()) { entry in LedgerDashboardWidgetView(entry: entry) }
            .configurationDisplayName("Resumo financeiro")
            .description("Saldo, entradas, saídas e próximos pagamentos. Atualizado pelo app.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    var body: some Widget {
        LedgerDashboardWidget()
        if #available(iOS 18.0, *) {
            LedgerExpenseControl()
            LedgerIncomeControl()
            LedgerDashboardControl()
            LedgerAgendaControl()
        }
    }
}
