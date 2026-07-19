import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ReflectionMaskDetectorTests {

    private let detector = ReflectionMaskDetector()

    @Test func findsBrightGlareOnDarkArtwork() throws {
        let size = CGSize(width: 600, height: 400)
        let glare = CGRect(x: 220, y: 260, width: 120, height: 60)
        let image = FixtureImageFactory.glareImage(size: size, glareRect: glare)
        let mask = try #require(detector.detectMask(in: image))
        // Analysis size ≤ 1024, so no downscale here: mask is 600×400.
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 280, y: 290)) > 0.9)  // glare center
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

    /// Real glare with a color cast (skylight streak) is washed out toward
    /// white — pale, slightly tinted, locally elevated. It must be proposed
    /// even though it is not pure white. (Vividly saturated color, by
    /// contrast, is painted content and stays unmarked — see below.)
    @Test func paleTintedSheenIsDetected() throws {
        let size = CGSize(width: 600, height: 400)
        let image = FixtureImageFactory.drawnImage(size: size) { context in
            context.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            // Washed-out cyan-tinted sheen: bright, low saturation.
            context.setFillColor(CGColor(red: 0.82, green: 0.92, blue: 0.95, alpha: 1))
            context.fillEllipse(in: CGRect(x: 240, y: 270, width: 120, height: 50))
        }
        let mask = try #require(detector.detectMask(in: image))
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 300, y: 295)) > 0.9)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 60, y: 60)) < 0.1)
    }

    /// Vividly saturated bright color is painted content, not glare.
    @Test func vividColorIsNotGlare() {
        let size = CGSize(width: 600, height: 400)
        let image = FixtureImageFactory.drawnImage(size: size) { context in
            context.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 0.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: 240, y: 270, width: 120, height: 50))
        }
        #expect(detector.detectMask(in: image) == nil)
    }

    /// Regression: large uniformly bright content (white wall, bright dress,
    /// painted sky) was falsely marked by the old global threshold. A flat
    /// bright region larger than the opening window is background, not glare
    /// — nothing may be proposed, including at its boundary.
    @Test func largeBrightRegionIsNotGlare() {
        let size = CGSize(width: 600, height: 400)
        let image = FixtureImageFactory.drawnImage(size: size) { context in
            context.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: 150, y: 80, width: 300, height: 240))
        }
        #expect(detector.detectMask(in: image) == nil)
    }

    /// Isolated speckle (sensor noise, tiny sparkles) must not survive the
    /// minimum-blob filter.
    @Test func tinySpeckleIsIgnored() {
        let size = CGSize(width: 600, height: 400)
        let image = FixtureImageFactory.drawnImage(size: size) { context in
            context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            for point in [CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 300), CGPoint(x: 520, y: 90)] {
                context.fill(CGRect(x: point.x, y: point.y, width: 3, height: 3))
            }
        }
        #expect(detector.detectMask(in: image) == nil)
    }

    /// The corrected image carries a band of real wall around the artwork;
    /// bright wall must never be proposed. Glare inside the band is ignored,
    /// the same blob away from the border is kept.
    @Test func borderBandIsExcluded() throws {
        let size = CGSize(width: 600, height: 400)
        let nearEdge = CGRect(x: 10, y: 170, width: 60, height: 40)   // inside 80px band
        let image = FixtureImageFactory.glareImage(size: size, glareRect: nearEdge)
        #expect(detector.detectMask(in: image, excludingBorder: 80) == nil)
        // Same image without exclusion: detected.
        let mask = try #require(detector.detectMask(in: image))
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 40, y: 190)) > 0.9)
    }
}
