import SwiftUI
import Observation

enum TrackrAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "Automática" : (self == .light ? "Clara" : "Escura") }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

enum TrackrAccent: String, CaseIterable, Identifiable {
    case teal, blue, indigo, green, orange, pink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .teal: return "Verde-petróleo"
        case .blue: return "Azul"
        case .indigo: return "Índigo"
        case .green: return "Verde"
        case .orange: return "Laranja"
        case .pink: return "Rosa"
        }
    }
    var color: Color {
        switch self {
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
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
