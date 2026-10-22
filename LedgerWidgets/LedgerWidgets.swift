import WidgetKit
import SwiftUI

private struct LedgerEntry: TimelineEntry { let date: Date }

private struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry { LedgerEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LedgerEntry) -> Void) { completion(LedgerEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerEntry>) -> Void) {
        completion(Timeline(entries: [LedgerEntry(date: .now)], policy: .never))
    }
}

private struct LedgerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if family == .accessoryCircular {
                Link(destination: URL(string: "ledger://expense")!) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }.accessibilityLabel("Nova despesa no Ledger")
            } else if family == .accessoryRectangular {
                Link(destination: URL(string: "ledger://agenda")!) {
                    VStack(alignment: .leading) {
                        Label("Ledger", systemImage: "calendar")
                        Text("Consultar pagamentos").font(.caption)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ledger", systemImage: "square.3.layers.3d").font(.headline)
                    if family == .systemMedium {
                        HStack(spacing: 16) {
                            action("Despesa", symbol: "minus.circle.fill", destination: "expense")
                            action("Receita", symbol: "plus.circle.fill", destination: "income")
                            action("Agenda", symbol: "calendar", destination: "agenda")
                        }
                    } else {
                        action("Nova despesa", symbol: "minus.circle", destination: "expense")
                        Text("Toque para registrar").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .tint(.teal)
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        .widgetURL(URL(string: family == .systemSmall || family == .accessoryCircular ? "ledger://expense" : (family == .accessoryRectangular ? "ledger://agenda" : "ledger://dashboard")))
    }
    private func action(_ title: String, symbol: String, destination: String) -> some View {
        Link(destination: URL(string: "ledger://\(destination)")!) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title2).widgetAccentable()
                Text(title).font(.subheadline.weight(.medium))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct LedgerQuickActionsWidget: Widget {
    let kind = "LedgerQuickActions"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerProvider()) { _ in LedgerWidgetView() }
            .configurationDisplayName("Acesso rápido")
            .description("Registre uma despesa, uma receita ou consulte a Agenda do Ledger.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
