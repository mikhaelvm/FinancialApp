import SwiftUI

@MainActor enum TrackrTheme {
    static var accent: Color {
        TrackrThemeState.shared.accent.color
    }
    static let cornerRadius: CGFloat = 18
    static let rowSpacing: CGFloat = 12
    static let income: Color = .green
    static let expense: Color = .orange
}

struct TrackrSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: TrackrTheme.cornerRadius))
    }
}

extension View {
    func trackrSurface() -> some View { modifier(TrackrSurface()) }
    func trackrListScreen(_ title: String, largeTitle: Bool = true) -> some View {
        self.modifier(TrackrRefreshModifier()).listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(largeTitle ? .large : .inline)
    }
    func trackrFormScreen(_ title: String) -> some View {
        self.formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct SymbolTile: View {
    let symbol: String
    var tint: Color = TrackrTheme.accent
    var body: some View {
        Image(systemName: symbol).font(.title3.weight(.semibold))
            .foregroundStyle(tint).frame(width: 44, height: 44)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct TrackrSummaryHeader: View {
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    let eyebrow: String
    let title: String
    let subtitle: String
    var symbol: String = "chart.line.uptrend.xyaxis"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(eyebrow, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(hideAmounts ? "••••" : title).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Color.primary)
                .minimumScaleFactor(0.7)
            Text(hideAmounts ? "Valores ocultos" : subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: TrackrTheme.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

struct TrackrActionTile: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 10))
            layout {
                Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 10).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 56 : 88)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: TrackrTheme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: TrackrTheme.cornerRadius).strokeBorder(tint.opacity(0.25), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: TrackrTheme.cornerRadius))
        }.buttonStyle(TrackrTileButtonStyle()).accessibilityElement(children: .combine)
    }
}

private struct TrackrTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TrackrDashboardActions: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let expense: () -> Void
    let income: () -> Void
    let schedule: () -> Void
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            TrackrActionTile(title: "Despesa", symbol: "minus.circle.fill", tint: TrackrTheme.expense, action: expense)
            TrackrActionTile(title: "Receita", symbol: "plus.circle.fill", tint: TrackrTheme.income, action: income)
            TrackrActionTile(title: "Agendar", symbol: "calendar.badge.plus", tint: TrackrTheme.accent, action: schedule)
        }.padding(.vertical, 6)
    }
}

struct PaymentCommitmentRow: View {
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    let item: PaymentCommitment
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(symbol: item.kind.symbol, tint: item.isOverdue() ? .orange : TrackrTheme.accent)
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
