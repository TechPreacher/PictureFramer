import SwiftUI

/// Image area plus controls, stacked on phones and side by side on wide
/// regular-width canvases. See `EditorLayout` for the rule.
struct AdaptiveEditorLayout<ImageArea: View, Controls: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let imageArea: ImageArea
    private let controls: Controls

    init(@ViewBuilder imageArea: () -> ImageArea, @ViewBuilder controls: () -> Controls) {
        self.imageArea = imageArea()
        self.controls = controls()
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = EditorLayout.resolve(
                canvasSize: proxy.size,
                isRegularWidth: horizontalSizeClass == .regular
            )
            switch layout {
            case .stacked:
                VStack(spacing: 12) {
                    imageArea
                    controls
                }
            case .sideBySide(let controlsWidth):
                HStack(alignment: .center, spacing: 16) {
                    imageArea
                    controls
                        .frame(width: controlsWidth)
                }
            }
        }
    }
}
