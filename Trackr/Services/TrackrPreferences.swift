import SwiftUI
import Observation

enum TrackrAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "Automática" : (self == .light ? "Clara" : "Escura") }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

enum TrackrAccent: String, CaseIterable, Identifiable {
    case blue, indigo, orange, pink, green, teal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blue: return "Azul"
        case .indigo: return "Índigo"
        case .orange: return "Laranja"
        case .pink: return "Rosa"
        case .green: return "Verde"
        case .teal: return "Verde-petróleo"
        }
    }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .orange: return .orange
        case .pink: return .pink
        case .green: return .green
        case .teal: return .teal
        }
    }
}

enum TrackrPreferences {
    static var monthlyBudgetCents: Int64 { Int64(UserDefaults.standard.double(forKey: "trackr.monthlyBudgetCents")) }
    static var hidesAmounts: Bool { UserDefaults.standard.bool(forKey: "trackr.hideAmounts") }
    static func display(_ cents: Int64) -> String { hidesAmounts ? "••••" : Money.format(cents) }
}

@MainActor @Observable
final class TrackrThemeState {
    static let shared = TrackrThemeState()
    var accent = TrackrAccent(rawValue: UserDefaults.standard.string(forKey: "trackr.accent") ?? "blue") ?? .blue
    func refresh() { accent = TrackrAccent(rawValue: UserDefaults.standard.string(forKey: "trackr.accent") ?? "blue") ?? .blue }
}
