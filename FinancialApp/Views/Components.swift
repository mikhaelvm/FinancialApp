import SwiftUI

extension Binding where Value == String {
    var bankCurrency: Binding<String> {
        Binding(get: { Money.bankInput(wrappedValue, previous: wrappedValue) },
                set: { wrappedValue = Money.bankInput($0, previous: wrappedValue) })
    }
}

/// Icon-only presentation with a meaningful VoiceOver label.
struct LedgerToolbarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) { Label(title, systemImage: systemImage) }
            .labelStyle(.iconOnly)
            .accessibilityLabel(Text(title))
    }
}

struct MoneyRow: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    let title: String
    let cents: Int64
    var symbol: String = "banknote"
    var tint: Color = .primary
    var body: some View {
        LabeledContent {
            Text(hideAmounts ? "••••" : Money.format(cents)).monospacedDigit().foregroundStyle(tint)
        } label: {
            Label(title, systemImage: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CategoryLabel: View {
    let category: Category?
    var body: some View {
        Label(category?.name ?? "Sem categoria", systemImage: category?.symbol ?? "square.grid.2x2")
            .foregroundStyle(category?.color ?? .secondary)
    }
}

extension CategoryExpense {
    var color: Color {
        switch colorName {
        case "purple": return .purple
        case "orange": return .orange
        case "blue": return .blue
        case "green": return .green
        case "pink": return .pink
        case "red": return .red
        default: return .teal
        }
    }
}

struct CategoryExpenseRow: View {
    let item: CategoryExpense
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: item.symbol, tint: item.color)
            Text(item.name)
            Spacer(minLength: 8)
            Text(hideAmounts ? "••••" : Money.format(item.cents)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
}

struct ErrorAlert: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Não foi possível concluir", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}

extension View {
    func financeError(_ message: Binding<String?>) -> some View { modifier(ErrorAlert(message: message)) }
}
