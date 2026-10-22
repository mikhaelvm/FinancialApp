import SwiftUI
import SwiftData
import UserNotifications
import AppIntents

@main
struct FinancialApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    @AppStorage("ledger.appearance") private var appearance = "system"
    @AppStorage("ledger.accent") private var accent = "teal"

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
                RootView().modelContainer(container)
                    .tint((LedgerAccent(rawValue: accent) ?? .teal).color)
                    .preferredColorScheme((LedgerAppearance(rawValue: appearance) ?? .system).colorScheme)
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
