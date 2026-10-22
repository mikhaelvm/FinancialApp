import SwiftUI
import SwiftData

@main
struct FinancialApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            container = try Persistence.makeContainer()
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
