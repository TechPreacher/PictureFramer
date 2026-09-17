import CoreGraphics

/// Decides how an editor screen arranges its image area and its controls.
///
/// Phones (compact width) always stack. Wide canvases with a regular
/// horizontal size class — iPad, iPhone Duo's inner display in landscape,
/// or a wide Split View pane — put the controls beside the image so the
/// picture keeps its height. A tall regular-width canvas (Duo inner display
/// in portrait) still stacks: the image has room and a narrow side column
/// would waste width. Decided on size classes and geometry, never on
/// interface orientation, as Apple recommends for iPhone Duo.
enum EditorLayout: Equatable, Sendable {
    case stacked
    case sideBySide(controlsWidth: CGFloat)

    /// Preferred width of the side column, capped so segmented pickers and
    /// sliders don't stretch.
    static let maxControlsWidth: CGFloat = 380
    /// Fraction of the canvas width the side column may take at most.
    static let maxControlsFraction: CGFloat = 0.42

    static func resolve(canvasSize: CGSize, isRegularWidth: Bool) -> EditorLayout {
        guard isRegularWidth,
              canvasSize.width > canvasSize.height,
              canvasSize.height > 0 else { return .stacked }
        let width = min(maxControlsWidth, canvasSize.width * maxControlsFraction)
        return .sideBySide(controlsWidth: width)
    }
}
