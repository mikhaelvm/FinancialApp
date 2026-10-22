import SwiftUI
import SwiftData
import Combine

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var error: String?
    @State private var initialized = false
    @State private var router = LedgerRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { DashboardView() }
                .tabItem { Label("Resumo", systemImage: "chart.pie.fill") }.tag(LedgerTab.dashboard)
            NavigationStack { TransactionsView() }
                .tabItem { Label("Extrato", systemImage: "list.bullet.rectangle") }.tag(LedgerTab.transactions)
            NavigationStack(path: $router.cardPath) { CreditCardsView() }
                .tabItem { Label("Cartões", systemImage: "creditcard") }.tag(LedgerTab.cards)
            NavigationStack { PaymentsView() }
                .tabItem { Label("Pagamentos", systemImage: "calendar") }.tag(LedgerTab.agenda)
        }
        .environment(router)
        .onOpenURL { router.open($0) }
        .sheet(isPresented: $router.showNewExpense) { AddTransactionView() }
        .sheet(isPresented: $router.showNewIncome) { AddTransactionView(initialKind: .income) }
        .onReceive(NotificationCenter.default.publisher(for: FinanceEvents.didChange)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)) { _ in
                NotificationService.shared.refresh(context: context)
                WidgetSnapshotService.refresh(context: context)
            }
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .task {
            // Also catches midnight while the app stays open; no background entitlement required.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if scenePhase == .active { refresh() }
            }
        }
        .financeError($error)
    }

    private func refresh() {
        LedgerThemeState.shared.refresh()
        do {
            if !initialized { try Persistence.seed(context: context); initialized = true }
            try RecurrenceEngine().synchronize(context: context)
            NotificationService.shared.refresh(context: context)
            WidgetSnapshotService.refresh(context: context)
        } catch { self.error = error.localizedDescription }
    }
}
