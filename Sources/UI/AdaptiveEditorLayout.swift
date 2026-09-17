import SwiftUI

/// Image area plus controls: stacked on tall canvases, side by side on wide
/// ones. See `EditorLayout` for the rule.
///
/// In the side column the `controls` scroll if they must, while `actions`
/// (the primary buttons) stay pinned underneath so Save is always visible
/// on a short phone-landscape canvas.
struct AdaptiveEditorLayout<ImageArea: View, Controls: View, Actions: View>: View {
    private let imageArea: ImageArea
    private let controls: Controls
    private let actions: Actions

    init(
        @ViewBuilder imageArea: () -> ImageArea,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder actions: () -> Actions
    ) {
        self.imageArea = imageArea()
        self.controls = controls()
        self.actions = actions()
    }

    var body: some View {
        GeometryReader { proxy in
            let isShort = proxy.size.height < EditorLayout.shortCanvasHeight
            let spacing: CGFloat = isShort ? 8 : 12
            Group {
                switch EditorLayout.resolve(canvasSize: proxy.size) {
                case .stacked:
                    VStack(spacing: spacing) {
                        imageArea
                        controls
                        actions
                    }
                case .sideBySide(let controlsWidth):
                    HStack(alignment: .center, spacing: 16) {
                        imageArea
                        VStack(spacing: spacing) {
                            ScrollView {
                                controls
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            actions
                        }
                        .frame(width: controlsWidth)
                    }
                }
            }
            .environment(\.editorCanvasIsShort, isShort)
        }
    }
}

extension AdaptiveEditorLayout where Actions == EmptyView {
    init(@ViewBuilder imageArea: () -> ImageArea, @ViewBuilder controls: () -> Controls) {
        self.init(imageArea: imageArea, controls: controls, actions: { EmptyView() })
    }
}

/// True when the editor canvas is shorter than `EditorLayout.shortCanvasHeight`
/// (a phone in landscape); control stacks tighten their spacing.
private struct EditorCanvasIsShortKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var editorCanvasIsShort: Bool {
        get { self[EditorCanvasIsShortKey.self] }
        set { self[EditorCanvasIsShortKey.self] = newValue }
    }
}
