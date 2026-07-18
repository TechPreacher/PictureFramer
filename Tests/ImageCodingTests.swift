import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ImageCodingTests {

    @Test func pngRoundTripsPixels() throws {
        let image = FixtureImageFactory.noiseImage(size: CGSize(width: 64, height: 48), seed: 7)
        let data = try #require(pngData(from: image))
        let decoded = try #require(cgImage(fromEncoded: data))
        #expect(decoded.width == 64 && decoded.height == 48)
        let a = PixelSampler(image: image)
        let b = PixelSampler(image: decoded)
        for x in stride(from: 2, to: 64, by: 7) {
            for y in stride(from: 2, to: 48, by: 7) {
                let p = CGPoint(x: x, y: y)
                #expect(abs(a.grayValue(atCanonical: p) - b.grayValue(atCanonical: p)) < 0.02)
            }
        }
    }

    @Test func resizeChangesPixelSize() throws {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 100, height: 50), gray: 0.5)
        let out = try #require(resized(image, to: CGSize(width: 30, height: 40)))
        #expect(out.width == 30 && out.height == 40)
    }

    @Test func croppedCanonicalTakesLowerLeftRect() throws {
        // Image dark everywhere except a light square in the canonical
        // lower-left corner.
        let image = FixtureImageFactory.drawnImage(size: CGSize(width: 100, height: 80)) { ctx in
            ctx.setFillColor(gray: 0.1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            ctx.setFillColor(gray: 0.9, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))   // canonical lower-left
        }
        let crop = try #require(croppedCanonical(image, to: CGRect(x: 0, y: 0, width: 40, height: 30)))
        #expect(crop.width == 40 && crop.height == 30)
        let sampler = PixelSampler(image: crop)
        #expect(sampler.isLight(atCanonical: CGPoint(x: 20, y: 15)))
    }
}
