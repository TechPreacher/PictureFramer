import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ReflectionMaskDetectorTests {

    private let detector = ReflectionMaskDetector()

    @Test func findsBrightGlareOnDarkArtwork() throws {
        let size = CGSize(width: 600, height: 400)
        let glare = CGRect(x: 200, y: 250, width: 150, height: 80)
        let image = FixtureImageFactory.glareImage(size: size, glareRect: glare)
        let mask = try #require(detector.detectMask(in: image))
        // Analysis size ≤ 1024, so no downscale here: mask is 600×400.
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 275, y: 290)) > 0.9)  // glare center
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 50, y: 50)) < 0.1)    // clean corner
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 550, y: 350)) < 0.1)  // clean corner
    }

    @Test func cleanDarkImageYieldsNil() {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 300, height: 200), gray: 0.3)
        #expect(detector.detectMask(in: image) == nil)
    }

    @Test func largeImageMaskIsDownscaled() throws {
        let size = CGSize(width: 2048, height: 1536)
        let glare = CGRect(x: 800, y: 900, width: 300, height: 200)
        let image = FixtureImageFactory.glareImage(size: size, glareRect: glare)
        let mask = try #require(detector.detectMask(in: image))
        #expect(max(mask.width, mask.height) <= 1024)
        // Scale glare center into mask space.
        let scale = CGFloat(mask.width) / size.width
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(
            atCanonical: CGPoint(x: 950 * scale, y: 1000 * scale)) > 0.9)
    }

    @Test func saturatedBrightColorIsNotGlare() {
        // Pure saturated red at high luminance-ish brightness — not glare.
        let size = CGSize(width: 300, height: 200)
        let image = FixtureImageFactory.drawnImage(size: size) { context in
            context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 100, y: 60, width: 100, height: 80))
        }
        #expect(detector.detectMask(in: image) == nil)
    }
}
