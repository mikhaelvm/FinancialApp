import SwiftUI
import SwiftData
import UserNotifications
import AppIntents

@main
struct TrackrApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    @AppStorage("trackr.appearance") private var appearance = "system"
    @AppStorage("trackr.accent") private var accent = "blue"
    @AppStorage("trackr.resetRevision") private var resetRevision = 0

    init() {
        UNUserNotificationCenter.current().delegate = TrackrNotificationDelegate.shared
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
                TrackrSecurityHost { RootView().modelContainer(container) }
                    .id(resetRevision)
                    .tint((TrackrAccent(rawValue: accent) ?? .blue).color)
                    .preferredColorScheme((TrackrAppearance(rawValue: appearance) ?? .system).colorScheme)
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
