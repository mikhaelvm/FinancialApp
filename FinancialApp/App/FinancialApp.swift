import SwiftUI
import SwiftData
import UserNotifications
import AppIntents

@main
struct FinancialApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        UNUserNotificationCenter.current().delegate = LedgerNotificationDelegate.shared
        do {
            container = try Persistence.sharedContainer()
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().modelContainer(container).tint(LedgerTheme.accent)
            } else {
                ContentUnavailableView {
                    Label("Não foi possível abrir os dados", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(startupError ?? "Falha ao abrir o armazenamento local. Tente reiniciar o app.")
                }
            }
        }
    }
}
