import CoreGraphics
import Testing
@testable import PictureFramer

struct CoordinateConversionTests {

    private let imageSize = CGSize(width: 4000, height: 3000)

    @Test func normalizedOriginMapsToPixelOrigin() {
        let corners = VisionQuadConversion.NormalizedCorners(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomLeft: CGPoint(x: 0, y: 0),
            bottomRight: CGPoint(x: 1, y: 0)
        )
        let quad = VisionQuadConversion.quad(fromNormalized: corners, imagePixelSize: imageSize)
        #expect(quad.bottomLeft == CGPoint(x: 0, y: 0))
        #expect(quad.topRight == CGPoint(x: 4000, y: 3000))
        #expect(quad.topLeft == CGPoint(x: 0, y: 3000))
        #expect(quad.bottomRight == CGPoint(x: 4000, y: 0))
    }

    @Test func normalizedQuadScalesExactly() {
        let corners = VisionQuadConversion.NormalizedCorners(
            topLeft: CGPoint(x: 0.1, y: 0.9),
            topRight: CGPoint(x: 0.85, y: 0.875),
            bottomLeft: CGPoint(x: 0.125, y: 0.2),
            bottomRight: CGPoint(x: 0.9, y: 0.15)
        )
        let quad = VisionQuadConversion.quad(fromNormalized: corners, imagePixelSize: imageSize)
        #expect(quad.topLeft == CGPoint(x: 400, y: 2700))
        #expect(quad.topRight == CGPoint(x: 3400, y: 2625))
        #expect(quad.bottomLeft == CGPoint(x: 500, y: 600))
        #expect(quad.bottomRight == CGPoint(x: 3600, y: 450))
    }

    /// No flip: larger normalized y must stay the larger pixel y.
    @Test func conversionPreservesVerticalOrder() {
        let corners = VisionQuadConversion.NormalizedCorners(
            topLeft: CGPoint(x: 0.2, y: 0.8),
            topRight: CGPoint(x: 0.8, y: 0.8),
            bottomLeft: CGPoint(x: 0.2, y: 0.3),
            bottomRight: CGPoint(x: 0.8, y: 0.3)
        )
        let quad = VisionQuadConversion.quad(fromNormalized: corners, imagePixelSize: imageSize)
        #expect(quad.topLeft.y > quad.bottomLeft.y)
        #expect(quad.topRight.y > quad.bottomRight.y)
    }
}
