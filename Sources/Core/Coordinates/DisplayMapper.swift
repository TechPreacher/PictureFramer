import CoreGraphics

/// Maps between canonical space (source-image pixels, lower-left origin)
/// and the display space of an aspect-fitted image in a view (points,
/// top-left origin). This is the only place in the app where a y-flip
/// happens.
struct DisplayMapper: Equatable, Sendable {
    let imagePixelSize: CGSize
    /// Where the aspect-fitted image lands inside the view, in view
    /// coordinates (top-left origin).
    let fittedRect: CGRect

    private let pointsPerPixel: CGFloat

    init(imagePixelSize: CGSize, viewSize: CGSize) {
        self.imagePixelSize = imagePixelSize
        let scale = min(
            viewSize.width / imagePixelSize.width,
            viewSize.height / imagePixelSize.height
        )
        pointsPerPixel = scale
        let fittedSize = CGSize(
            width: imagePixelSize.width * scale,
            height: imagePixelSize.height * scale
        )
        fittedRect = CGRect(
            x: (viewSize.width - fittedSize.width) / 2,
            y: (viewSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func displayPoint(fromPixel p: CGPoint) -> CGPoint {
        CGPoint(
            x: fittedRect.minX + p.x * pointsPerPixel,
            y: fittedRect.minY + (imagePixelSize.height - p.y) * pointsPerPixel
        )
    }

    func pixelPoint(fromDisplay p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - fittedRect.minX) / pointsPerPixel,
            y: imagePixelSize.height - (p.y - fittedRect.minY) / pointsPerPixel
        )
    }

    /// Canonical-space quad → display-space quad. Corner names keep their
    /// on-screen meaning: canonical topLeft (large y) lands at the top of
    /// the screen (small y).
    func displayQuad(from quad: Quad) -> Quad {
        Quad(
            topLeft: displayPoint(fromPixel: quad.topLeft),
            topRight: displayPoint(fromPixel: quad.topRight),
            bottomLeft: displayPoint(fromPixel: quad.bottomLeft),
            bottomRight: displayPoint(fromPixel: quad.bottomRight)
        )
    }

    func pixelQuad(fromDisplay quad: Quad) -> Quad {
        Quad(
            topLeft: pixelPoint(fromDisplay: quad.topLeft),
            topRight: pixelPoint(fromDisplay: quad.topRight),
            bottomLeft: pixelPoint(fromDisplay: quad.bottomLeft),
            bottomRight: pixelPoint(fromDisplay: quad.bottomRight)
        )
    }
}
