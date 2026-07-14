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
}
