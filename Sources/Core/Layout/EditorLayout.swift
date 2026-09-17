import CoreGraphics

/// How an editor screen arranges its image area and its controls.
///
/// Tall canvases (any phone in portrait, iPad in portrait, iPhone Duo's
/// inner display in portrait) stack the controls under the image. Wide
/// canvases (any device in landscape, a wide Split View pane) put the
/// controls in a side column so the picture keeps the full height — on a
/// phone in landscape the stack would leave under 100 pt for the image.
enum EditorLayout: Equatable, Sendable {
    case stacked
    case sideBySide(controlsWidth: CGFloat)

    /// Cap on the side column so segmented pickers and sliders don't stretch.
    static let maxControlsWidth: CGFloat = 380
    /// The side column may take at most this fraction of the canvas width.
    static let maxControlsFraction: CGFloat = 0.42
    /// On short canvases (a phone in landscape) the column gets half the
    /// width instead, so two-line labels collapse to one line and the whole
    /// control stack fits the height without scrolling.
    static let shortCanvasHeight: CGFloat = 500
    static let shortCanvasControlsFraction: CGFloat = 0.5

    static func resolve(canvasSize: CGSize) -> EditorLayout {
        guard CanvasShape(size: canvasSize) == .wide else { return .stacked }
        let fraction = canvasSize.height < shortCanvasHeight
            ? shortCanvasControlsFraction : maxControlsFraction
        let width = min(maxControlsWidth, canvasSize.width * fraction)
        return .sideBySide(controlsWidth: width)
    }
}
