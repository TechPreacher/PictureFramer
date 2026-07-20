import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ReflectionMaskTests {

    private let size = CGSize(width: 400, height: 300)

    private func gray(_ image: CGImage, atCanonical p: CGPoint) -> CGFloat {
        PixelSampler(image: image).grayValue(atCanonical: p)
    }

    @Test func emptyMaskRasterizesToNil() {
        let mask = ReflectionMask(imageSize: size)
        #expect(mask.isEmpty)
        #expect(mask.rasterize(scale: 1) == nil)
    }

    @Test func addStrokePaintsWhiteAlongPath() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 20,
                       points: [CGPoint(x: 100, y: 150), CGPoint(x: 200, y: 150)]))
        let raster = try #require(mask.rasterize(scale: 1))
        #expect(raster.width == 400 && raster.height == 300)
        #expect(gray(raster, atCanonical: CGPoint(x: 150, y: 150)) > 0.9)   // on the path
        #expect(gray(raster, atCanonical: CGPoint(x: 150, y: 145)) > 0.9)   // inside radius
        #expect(gray(raster, atCanonical: CGPoint(x: 150, y: 100)) < 0.1)   // far away
        #expect(gray(raster, atCanonical: CGPoint(x: 20, y: 20)) < 0.1)
    }

    @Test func eraseStrokeRemovesAddedArea() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 30, points: [CGPoint(x: 200, y: 150)]))
        mask.add(.init(mode: .erase, radius: 30, points: [CGPoint(x: 200, y: 150)]))
        let raster = try #require(mask.rasterize(scale: 1))
        #expect(gray(raster, atCanonical: CGPoint(x: 200, y: 150)) < 0.1)
    }

    @Test func singlePointStrokePaintsDot() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 15, points: [CGPoint(x: 50, y: 50)]))
        let raster = try #require(mask.rasterize(scale: 1))
        #expect(gray(raster, atCanonical: CGPoint(x: 50, y: 50)) > 0.9)
        #expect(gray(raster, atCanonical: CGPoint(x: 90, y: 50)) < 0.1)
    }

    @Test func rasterizationAgreesAcrossScales() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 40,
                       points: [CGPoint(x: 150, y: 100), CGPoint(x: 250, y: 200)]))
        let full = try #require(mask.rasterize(scale: 1))
        let half = try #require(mask.rasterize(scale: 0.5))
        #expect(half.width == 200 && half.height == 150)
        // Sample a grid; scaled mask must agree with full-res mask.
        for x in stride(from: 10, to: 390, by: 20) {
            for y in stride(from: 10, to: 290, by: 20) {
                let f = gray(full, atCanonical: CGPoint(x: x, y: y)) > 0.5
                let h = gray(half, atCanonical: CGPoint(x: x / 2, y: y / 2)) > 0.5
                // Allow disagreement only near the stroke boundary (within 4 px).
                let boundaryBand = abs(gray(full, atCanonical: CGPoint(x: x, y: y)) - 0.5) < 0.45
                if !boundaryBand {
                    #expect(f == h, "mismatch at (\(x), \(y))")
                }
            }
        }
    }

    @Test func detectedRasterScalesToTargetSize() throws {
        // 40×30 proposal with a white block lower-left quadrant.
        let proposal = FixtureImageFactory.solidImage(size: CGSize(width: 40, height: 30), gray: 0)
        var maskBytes = [UInt8](repeating: 0, count: 40 * 30)
        for y in 0..<15 { for x in 0..<20 { maskBytes[y * 40 + x] = 255 } }
        // Proposal bytes are row-major top-first; white block occupies the TOP rows
        // of memory, which is canonical y in 15..<30. Build via helper below.
        let raster = try #require(ReflectionMask.grayImage(from: maskBytes, width: 40, height: 30))
        var mask = ReflectionMask(imageSize: size, detectedRaster: raster)
        #expect(!mask.isEmpty)
        let full = try #require(mask.rasterize(scale: 1))
        // Memory top rows = canonical top → white in upper-left quadrant.
        #expect(gray(full, atCanonical: CGPoint(x: 100, y: 250)) > 0.9)
        #expect(gray(full, atCanonical: CGPoint(x: 300, y: 50)) < 0.1)
        mask.clear()
        #expect(mask.isEmpty)
    }
}
