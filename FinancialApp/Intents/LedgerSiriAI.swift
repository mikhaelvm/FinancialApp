// The CI enables this only when the selected Xcode includes the iOS 27 SDK.
// Older SDKs still compile the stable App Shortcuts in LedgerIntents.swift.
#if LEDGER_SIRI_AI
import AppIntents

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchLedgerWithSiriAI: ShowInAppSearchResultsIntent {
    static var searchScopes: [StringSearchScope] = [.general]
    static let isAssistantOnly = true
    var criteria: StringSearchCriteria

    @MainActor func perform() async throws -> some IntentResult {
        LedgerRouter.shared.search(criteria.term)
        return .result()
    }
}
#endif
