import CoreGraphics
import Testing
@testable import PictureFramer

struct DisplayMapperTests {

    private func expectClose(
        _ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 1e-9,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let distance = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        #expect(distance <= tolerance, "expected \(a) ≈ \(b)", sourceLocation: sourceLocation)
    }

    // MARK: Round trips

    @Test(arguments: [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 4000, y: 3000),
        CGPoint(x: 0, y: 3000),
        CGPoint(x: 4000, y: 0),
        CGPoint(x: 2000, y: 1500),
        CGPoint(x: 137.25, y: 2411.75),
        CGPoint(x: 3999.5, y: 0.5),
    ])
    func pixelDisplayRoundTrip(pixel: CGPoint) {
        let mapper = DisplayMapper(
            imagePixelSize: CGSize(width: 4000, height: 3000),
            viewSize: CGSize(width: 390, height: 700)
        )
        let roundTripped = mapper.pixelPoint(fromDisplay: mapper.displayPoint(fromPixel: pixel))
        expectClose(roundTripped, pixel, tolerance: 1e-6)
    }

    // MARK: Known values / y-flip

    @Test func canonicalOriginMapsToBottomLeftOfFittedRect() {
        let mapper = DisplayMapper(
            imagePixelSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 500, height: 500)
        )
        // Square image in square view: fitted rect fills the view.
        #expect(mapper.fittedRect == CGRect(x: 0, y: 0, width: 500, height: 500))
        // Pixel (0,0) is canonical bottom-left → display bottom-left (y = maxY).
        expectClose(mapper.displayPoint(fromPixel: .zero), CGPoint(x: 0, y: 500))
        // Pixel (0, h) is canonical top-left → display top-left.
        expectClose(mapper.displayPoint(fromPixel: CGPoint(x: 0, y: 1000)), CGPoint(x: 0, y: 0))
    }

    // MARK: Letterboxing

    @Test func portraitImageInLandscapeViewIsCenteredHorizontally() {
        let mapper = DisplayMapper(
            imagePixelSize: CGSize(width: 1000, height: 2000),
            viewSize: CGSize(width: 800, height: 400)
        )
        // Scale limited by height: 400/2000 = 0.2 → fitted 200×400 at x=300.
        #expect(mapper.fittedRect == CGRect(x: 300, y: 0, width: 200, height: 400))
        expectClose(mapper.displayPoint(fromPixel: .zero), CGPoint(x: 300, y: 400))
        expectClose(
            mapper.displayPoint(fromPixel: CGPoint(x: 1000, y: 2000)),
            CGPoint(x: 500, y: 0)
        )
    }

    @Test func landscapeImageInPortraitViewIsCenteredVertically() {
        let mapper = DisplayMapper(
            imagePixelSize: CGSize(width: 2000, height: 1000),
            viewSize: CGSize(width: 400, height: 800)
        )
        // Scale limited by width: 400/2000 = 0.2 → fitted 400×200 at y=300.
        #expect(mapper.fittedRect == CGRect(x: 0, y: 300, width: 400, height: 200))
        // Center of image maps to center of view.
        expectClose(
            mapper.displayPoint(fromPixel: CGPoint(x: 1000, y: 500)),
            CGPoint(x: 200, y: 400)
        )
    }

    // MARK: Quad mapping

    @Test func displayQuadKeepsOnScreenCornerMeaning() {
        let mapper = DisplayMapper(
            imagePixelSize: CGSize(width: 1000, height: 1000),
            viewSize: CGSize(width: 100, height: 100)
        )
        let quad = Quad(
            topLeft: CGPoint(x: 100, y: 900),
            topRight: CGPoint(x: 900, y: 900),
            bottomLeft: CGPoint(x: 100, y: 100),
            bottomRight: CGPoint(x: 900, y: 100)
        )
        let display = mapper.displayQuad(from: quad)
        // Canonical top (large y) is on-screen top (small y).
        #expect(display.topLeft.y < display.bottomLeft.y)
        expectClose(display.topLeft, CGPoint(x: 10, y: 10))
        expectClose(display.bottomRight, CGPoint(x: 90, y: 90))
        // Inverse restores the original quad.
        let restored = mapper.pixelQuad(fromDisplay: display)
        for (a, b) in zip(restored.perimeterCorners, quad.perimeterCorners) {
            expectClose(a, b, tolerance: 1e-6)
        }
    }

    // MARK: Extreme aspect ratios

    @Test(arguments: [
        CGSize(width: 10000, height: 1000),
        CGSize(width: 1000, height: 10000),
    ])
    func extremeAspectRatiosRoundTripWithoutDrift(imageSize: CGSize) {
        let mapper = DisplayMapper(imagePixelSize: imageSize, viewSize: CGSize(width: 390, height: 844))
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: imageSize.width, y: imageSize.height),
            CGPoint(x: imageSize.width / 3, y: imageSize.height / 7),
        ]
        for p in points {
            let roundTripped = mapper.pixelPoint(fromDisplay: mapper.displayPoint(fromPixel: p))
            expectClose(roundTripped, p, tolerance: 1e-5)
        }
    }
}
