import SwiftUI

/// Keep the familiar single list in portrait and in narrow iPad windows.
/// Wide windows get two independently scrollable, bounded columns.
struct TrackrAdaptiveSections<Primary: View, Secondary: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let primaryFraction: CGFloat
    private let primary: Primary
    private let secondary: Secondary

    init(primaryFraction: CGFloat = 0.55, @ViewBuilder primary: () -> Primary,
         @ViewBuilder secondary: () -> Secondary) {
        self.primaryFraction = primaryFraction
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad,
               geometry.size.width >= 950, geometry.size.width > geometry.size.height,
               !typeSize.isAccessibilitySize {
                let width = min(geometry.size.width, 1440)
                HStack(alignment: .top, spacing: 0) {
                    List { primary }.frame(width: width * primaryFraction)
                    List { secondary }.frame(width: width * (1 - primaryFraction))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                List { primary; secondary }
            }
        }
    }
}
