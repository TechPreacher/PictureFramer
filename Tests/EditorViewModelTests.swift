import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PictureFramer

struct EditorViewModelTests {

    @Test func fallbackQuadCoversCenteredEightyPercent() {
        let quad = EditorViewModel.fallbackQuad(for: CGSize(width: 1000, height: 500))
        #expect(quad.topLeft == CGPoint(x: 100, y: 450))
        #expect(quad.topRight == CGPoint(x: 900, y: 450))
        #expect(quad.bottomLeft == CGPoint(x: 100, y: 50))
        #expect(quad.bottomRight == CGPoint(x: 900, y: 50))
        #expect(quad.isConvex)
    }

    @Test func normalizedLoadBakesOrientationUpright() throws {
        // A JPEG with EXIF orientation 6 (rotate 90° CW to display) must
        // decode with width/height already swapped.
        let source = FixtureImageFactory.solidImage(size: CGSize(width: 400, height: 200))
        let exporter = PhotoLibraryExporter()
        var data = try exporter.encodeJPEG(source)
        data = try #require(Self.settingEXIFOrientation(6, in: data))
        let normalized = try #require(EditorViewModel.normalizedCGImage(from: data))
        #expect(normalized.width == 200)
        #expect(normalized.height == 400)
    }

    /// Re-encodes JPEG data with the given EXIF orientation tag.
    private static func settingEXIFOrientation(_ orientation: Int, in data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func makeDefaults() -> (UserDefaults, cleanup: () -> Void) {
        let suiteName = "EditorViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test @MainActor func cropModeDefaultsToFramedAndPersists() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let first = EditorViewModel(defaults: defaults)
        #expect(first.cropMode == .framed)
        first.cropMode = .paintingOnly
        let second = EditorViewModel(defaults: defaults)
        #expect(second.cropMode == .paintingOnly)
    }

    @Test @MainActor func paintingModeForcesEffectiveMarginToZero() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let model = EditorViewModel(defaults: defaults)
        model.marginPixels = 120
        #expect(model.effectiveMarginPixels == 120)
        model.cropMode = .paintingOnly
        #expect(model.effectiveMarginPixels == 0)
        #expect(model.marginPixels == 120)  // slider value survives the round trip
        model.cropMode = .framed
        #expect(model.effectiveMarginPixels == 120)
    }

    /// In painting mode marginQuad must be the quad itself (no expansion),
    /// so the overlay shows a single outline.
    @Test @MainActor func paintingModeMarginQuadEqualsQuad() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let model = EditorViewModel(defaults: defaults)
        model.cropMode = .paintingOnly  // set BEFORE source: no re-detection fires
        let size = CGSize(width: 1000, height: 800)
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 200)
        model.setSourceForTesting(FixtureImageFactory.solidImage(size: size), quad: quad)
        model.marginPixels = 100
        #expect(model.marginQuad == quad)
    }

    @Test @MainActor func switchingModeRerunsDetection() async throws {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let model = EditorViewModel(defaults: defaults)
        let size = CGSize(width: 1200, height: 900)
        let outer = FixtureImageFactory.axisAlignedQuad(in: size, inset: 150)
        let inner = try #require(outer.expanded(by: -120))
        let image = FixtureImageFactory.framedPaintingImage(
            size: size, outerQuad: outer, innerQuad: inner)
        model.setSourceForTesting(image, quad: outer)
        model.cropMode = .paintingOnly
        await model.detectionTask?.value
        let detected = try #require(model.quad)
        #expect(model.stage == .adjusting)
        // Re-detection must land on the painting, not keep the frame quad.
        let allowed = max(size.width, size.height) * 0.035
        for corner in detected.perimeterCorners {
            let nearest = inner.perimeterCorners
                .map { hypot(corner.x - $0.x, corner.y - $0.y) }
                .min()!
            #expect(nearest <= allowed)
        }
    }
}
