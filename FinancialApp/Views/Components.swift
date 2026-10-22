import SwiftUI

struct MoneyRow: View {
    let title: String
    let cents: Int64
    var symbol: String = "banknote"
    var tint: Color = .primary
    var body: some View {
        LabeledContent {
            Text(Money.format(cents)).monospacedDigit().foregroundStyle(tint)
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
