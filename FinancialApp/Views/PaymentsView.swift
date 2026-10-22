import SwiftUI

struct PaymentsView: View {
    @Environment(LedgerRouter.self) private var router
    var body: some View {
        Group {
            if router.paymentsSection == .calendar { PaymentAgendaView() }
            else { SubscriptionsView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Pagamentos", selection: Binding(get: { router.paymentsSection }, set: { router.paymentsSection = $0 })) {
                ForEach(PaymentsSection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8).background(.bar)
        }
    }
}
