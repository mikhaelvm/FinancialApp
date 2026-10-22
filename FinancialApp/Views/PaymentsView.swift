import SwiftUI

struct PaymentsView: View {
    @Environment(LedgerRouter.self) private var router
    var body: some View {
        Group {
            if router.paymentsSection == .calendar { PaymentAgendaView() }
            else { SubscriptionsView() }
        }
        .navigationTitle("Pagamentos")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct PaymentsSectionPicker: View {
    @Environment(LedgerRouter.self) private var router
    var body: some View {
        Section {
            Picker("Pagamentos", selection: Binding(get: { router.paymentsSection }, set: { router.paymentsSection = $0 })) {
                ForEach(PaymentsSection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
        }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
    }
}
