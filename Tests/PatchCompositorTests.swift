import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct PatchCompositorTests {

    private let size = CGSize(width: 200, height: 160)

    /// Binary mask: white rectangle blob, black elsewhere.
    private func blobMask(white rect: CGRect) -> CGImage {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: min(rect.width, rect.height) / 2,
                       points: [CGPoint(x: rect.midX, y: rect.midY)]))
        return mask.rasterize(scale: 1)!
    }

    @Test func boundingBoxCoversWhitePixels() throws {
        let mask = blobMask(white: CGRect(x: 80, y: 60, width: 40, height: 40))
        let box = try #require(PatchCompositor.maskBoundingBox(of: mask))
        #expect(box.contains(CGPoint(x: 100, y: 80)))
        #expect(box.minX > 40 && box.maxX < 160)
        #expect(box.minY > 20 && box.maxY < 140)
    }

    @Test func blackMaskHasNoBoundingBox() {
        let black = ReflectionMask.grayImage(
            from: [UInt8](repeating: 0, count: 50 * 40), width: 50, height: 40)!
        #expect(PatchCompositor.maskBoundingBox(of: black) == nil)
    }

    @Test func compositeLeavesOutsideMaskBitIdentical() throws {
        let original = FixtureImageFactory.noiseImage(size: size, seed: 42)
        let mask = blobMask(white: CGRect(x: 80, y: 60, width: 40, height: 40))
        let patchRect = try #require(PatchCompositor.maskBoundingBox(of: mask))
        let patch = FixtureImageFactory.solidImage(
            size: CGSize(width: 50, height: 50), gray: 1.0)
        let result = try #require(PatchCompositor.composite(
            original: original, patch: patch, patchRect: patchRect, mask: mask))
        let maskSampler = PixelSampler(image: mask)
        let a = PixelSampler(image: original)
        let b = PixelSampler(image: result)
        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                let p = CGPoint(x: x, y: y)
                if maskSampler.grayValue(atCanonical: p) == 0 {
                    #expect(a.grayValue(atCanonical: p) == b.grayValue(atCanonical: p),
                            "pixel changed outside mask at (\(x), \(y))")
                }
            }
        }
        // Inside the mask (well inside, away from any antialiased edge):
        #expect(b.grayValue(atCanonical: CGPoint(x: 100, y: 80)) > 0.9)
        #expect(a.grayValue(atCanonical: CGPoint(x: 100, y: 80)) < 0.9
                || b.grayValue(atCanonical: CGPoint(x: 100, y: 80)) > 0.9)
    }

    @Test func featheredMaskNeverExpandsBeyondBinaryMask() throws {
        let mask = blobMask(white: CGRect(x: 80, y: 60, width: 40, height: 40))
        let feathered = try #require(PatchCompositor.featheredMask(from: mask, radius: 5))
        #expect(feathered.width == mask.width && feathered.height == mask.height)
        let binary = PixelSampler(image: mask)
        let soft = PixelSampler(image: feathered)
        for x in stride(from: 0, to: Int(size.width), by: 2) {
            for y in stride(from: 0, to: Int(size.height), by: 2) {
                let p = CGPoint(x: x, y: y)
                if binary.grayValue(atCanonical: p) == 0 {
                    #expect(soft.grayValue(atCanonical: p) == 0,
                            "feather leaked outside mask at (\(x), \(y))")
                }
            }
        }
    }
}
