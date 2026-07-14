import CoreGraphics

/// The only place in the app where Vision's normalized coordinates are
/// interpreted. Vision reports corners normalized to [0, 1] with a
/// lower-left origin; canonical space is also lower-left, so conversion is
/// a pure scale — deliberately no y-flip.
enum VisionQuadConversion {

    struct NormalizedCorners {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomLeft: CGPoint
        var bottomRight: CGPoint
    }

    /// Scales Vision-normalized corners into canonical full-resolution
    /// pixel space.
    static func quad(fromNormalized corners: NormalizedCorners, imagePixelSize: CGSize) -> Quad {
        func scale(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * imagePixelSize.width, y: p.y * imagePixelSize.height)
        }
        return Quad(
            topLeft: scale(corners.topLeft),
            topRight: scale(corners.topRight),
            bottomLeft: scale(corners.bottomLeft),
            bottomRight: scale(corners.bottomRight)
        )
    }
}
