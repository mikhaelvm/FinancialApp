import SwiftUI

@MainActor enum LedgerTheme {
    static var accent: Color {
        LedgerThemeState.shared.accent.color
    }
    static let navy = Color(red: 0.04, green: 0.10, blue: 0.19)
    static let teal = Color(red: 0.04, green: 0.40, blue: 0.43)
    static let hero = LinearGradient(colors: [teal, navy], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct LedgerSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func ledgerSurface() -> some View { modifier(LedgerSurface()) }
}

struct SymbolTile: View {
    let symbol: String
    var tint: Color = LedgerTheme.accent
    var body: some View {
        Image(systemName: symbol).font(.title3.weight(.semibold))
            .foregroundStyle(tint).frame(width: 44, height: 44)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct LedgerSummaryHeader: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    let eyebrow: String
    let title: String
    let subtitle: String
    var symbol: String = "chart.line.uptrend.xyaxis"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(eyebrow, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(hideAmounts ? "••••" : title).font(.largeTitle.bold()).monospacedDigit().foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
            Text(hideAmounts ? "Valores ocultos" : subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct PaymentCommitmentRow: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    let item: PaymentCommitment
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(symbol: item.kind.symbol, tint: item.isOverdue() ? .orange : LedgerTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).foregroundStyle(.primary)
                Text(item.detail.isEmpty ? item.kind.title : "\(item.kind.title) • \(item.detail)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(item.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.medium)).foregroundStyle(item.isOverdue() ? .orange : .secondary)
            }
            Spacer(minLength: 4)
            Text(hideAmounts ? "••••" : Money.format(item.amountCents)).font(.subheadline.weight(.semibold))
                .monospacedDigit().foregroundStyle(.primary)
        }
        .padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}
