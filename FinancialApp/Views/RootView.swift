import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var error: String?
    @State private var initialized = false

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Resumo", systemImage: "chart.bar.xaxis") }
            NavigationStack { TransactionsView() }
                .tabItem { Label("Transações", systemImage: "arrow.left.arrow.right") }
            NavigationStack { CreditCardsView() }
                .tabItem { Label("Cartões", systemImage: "creditcard") }
            NavigationStack { SubscriptionsView() }
                .tabItem { Label("Assinaturas", systemImage: "repeat") }
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
        do {
            if !initialized { try Persistence.seed(context: context); initialized = true }
            try RecurrenceEngine().synchronize(context: context)
        } catch { self.error = error.localizedDescription }
    }
}
