import SwiftUI
import SwiftData

struct TrackrRefreshModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var error: String?
    func body(content: Content) -> some View {
        content.refreshable {
            do { try await GoogleDriveBackupService.shared.refreshFromGesture(context: context) }
            catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
        }
        .background { Color.clear.frame(width: 0, height: 0).financeError($error) }
    }
}
