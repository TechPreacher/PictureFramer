import CoreGraphics

/// Pure coordinate math for the corner-drag magnifier loupe. Projects
/// image-display-space points into the loupe's own circle-space and decides
/// which top corner the loupe parks in (opposite the finger). UI-free so it
/// can be unit-tested; the SwiftUI `MagnifierLoupeView` renders using it.
struct LoupeGeometry: Equatable {
    /// The point in image-display space the loupe is centered on — the
    /// corner's current on-screen landing point.
    let focusDisplay: CGPoint
    let magnification: CGFloat
    let diameter: CGFloat

    /// Center of the loupe in its own coordinate space.
    var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    /// Maps a point in image-display space into loupe circle-space. The
    /// focus point maps to `center`; everything else fans out by
    /// `magnification`.
    func project(_ displayPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (displayPoint.x - focusDisplay.x) * magnification + center.x,
            y: (displayPoint.y - focusDisplay.y) * magnification + center.y
        )
    }

    /// The loupe's frame within the image area. Pinned to the top; placed on
    /// the side opposite the focus's horizontal half so the finger never
    /// covers it. A focus on the midline (or right of it) parks the loupe
    /// on the left.
    static func placement(
        focusDisplay: CGPoint, areaSize: CGSize, diameter: CGFloat, margin: CGFloat
    ) -> CGRect {
        let focusOnRightHalf = focusDisplay.x >= areaSize.width / 2
        let x = focusOnRightHalf ? margin : areaSize.width - diameter - margin
        return CGRect(x: x, y: margin, width: diameter, height: diameter)
    }
}
