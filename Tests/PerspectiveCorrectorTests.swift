import CoreGraphics
import Testing
@testable import PictureFramer

struct PerspectiveCorrectorTests {

    private let corrector = PerspectiveCorrector()
    private let size = CGSize(width: 1200, height: 900)

    private func averageEdgeLengths(of quad: Quad) -> (width: CGFloat, height: CGFloat) {
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }
        let width = (distance(quad.topLeft, quad.topRight) + distance(quad.bottomLeft, quad.bottomRight)) / 2
        let height = (distance(quad.topLeft, quad.bottomLeft) + distance(quad.topRight, quad.bottomRight)) / 2
        return (width, height)
    }

    @Test func axisAlignedQuadIsIdentityCrop() throws {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 200)
        let image = FixtureImageFactory.image(size: size, quad: quad)
        let output = try #require(corrector.correct(image, quad: quad))
        // 800×500 region → output matches within a pixel.
        #expect(abs(CGFloat(output.width) - 800) <= 1)
        #expect(abs(CGFloat(output.height) - 500) <= 1)
    }

    @Test func keystonedQuadStraightens() throws {
        let quad = FixtureImageFactory.keystonedQuad(in: size, inset: 150, topPinch: 90)
        let image = FixtureImageFactory.image(size: size, quad: quad)
        let output = try #require(corrector.correct(image, quad: quad))
        let sampler = PixelSampler(image: output)
        let w = CGFloat(output.width)
        let h = CGFloat(output.height)

        // CIPerspectiveCorrection reconstructs the rectangle's true
        // proportions via homography, so the output can differ noticeably
        // from raw edge lengths — assert the neighborhood, not the exact
        // size.
        let expected = averageEdgeLengths(of: quad)
        #expect(abs(w - expected.width) / expected.width < 0.4)
        #expect(abs(h - expected.height) / expected.height < 0.4)

        // Center is picture-dark.
        #expect(sampler.isDark(atCanonical: CGPoint(x: w / 2, y: h / 2)))
        // The picture now fills the output rect: just inside every corner
        // is dark (frame stroke is 0.45 gray → still < 0.5 threshold).
        let inset: CGFloat = 20
        for point in [
            CGPoint(x: inset, y: inset),
            CGPoint(x: w - inset, y: inset),
            CGPoint(x: inset, y: h - inset),
            CGPoint(x: w - inset, y: h - inset),
        ] {
            #expect(sampler.grayValue(atCanonical: point) < 0.5, "corner region not dark at \(point)")
        }
    }

    @Test func marginExpandedQuadKeepsRealBackground() throws {
        let margin: CGFloat = 60
        let quad = FixtureImageFactory.keystonedQuad(in: size, inset: 200, topPinch: 70)
        let image = FixtureImageFactory.image(size: size, quad: quad)

        let tight = try #require(corrector.correct(image, quad: quad))
        let expanded = try #require(quad.expanded(by: margin))
        let withMargin = try #require(corrector.correct(image, quad: expanded))

        // Output grows by roughly 2·margin per dimension (homography
        // rescaling makes this approximate: assert 1–3× margin per side).
        #expect(CGFloat(withMargin.width - tight.width) > margin)
        #expect(CGFloat(withMargin.width - tight.width) < 3 * margin)
        #expect(CGFloat(withMargin.height - tight.height) > margin)
        #expect(CGFloat(withMargin.height - tight.height) < 3 * margin)

        // The margin band contains REAL light background pixels — proof the
        // expansion sampled the source image, not synthetic padding.
        let sampler = PixelSampler(image: withMargin)
        let w = CGFloat(withMargin.width)
        let h = CGFloat(withMargin.height)
        let band = margin / 2
        for point in [
            CGPoint(x: w / 2, y: band),            // bottom band
            CGPoint(x: w / 2, y: h - band),        // top band
            CGPoint(x: band, y: h / 2),            // left band
            CGPoint(x: w - band, y: h / 2),        // right band
        ] {
            #expect(sampler.isLight(atCanonical: point), "margin band not background at \(point)")
        }
        // And the picture is still dark in the middle.
        #expect(sampler.isDark(atCanonical: CGPoint(x: w / 2, y: h / 2)))
    }

    @Test func nonConvexQuadReturnsNil() {
        let image = FixtureImageFactory.solidImage(size: size)
        let bowtie = Quad(
            topLeft: CGPoint(x: 800, y: 700),
            topRight: CGPoint(x: 200, y: 700),
            bottomLeft: CGPoint(x: 200, y: 200),
            bottomRight: CGPoint(x: 800, y: 200)
        )
        #expect(corrector.correct(image, quad: bowtie) == nil)
    }
}
