import SwiftUI
import Observation

enum LedgerAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "Automática" : (self == .light ? "Clara" : "Escura") }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

enum LedgerAccent: String, CaseIterable, Identifiable {
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
        case .teal: return Color("AccentColor")
        case .blue: return .blue
        case .indigo: return .indigo
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

enum LedgerPreferences {
    static var monthlyBudgetCents: Int64 { Int64(UserDefaults.standard.double(forKey: "ledger.monthlyBudgetCents")) }
    static var hidesAmounts: Bool { UserDefaults.standard.bool(forKey: "ledger.hideAmounts") }
    static func display(_ cents: Int64) -> String { hidesAmounts ? "••••" : Money.format(cents) }
}

@MainActor @Observable
final class LedgerThemeState {
    static let shared = LedgerThemeState()
    var accent = LedgerAccent(rawValue: UserDefaults.standard.string(forKey: "ledger.accent") ?? "teal") ?? .teal
    func refresh() { accent = LedgerAccent(rawValue: UserDefaults.standard.string(forKey: "ledger.accent") ?? "teal") ?? .teal }
}
