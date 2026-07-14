import CoreGraphics
import Testing
@testable import PictureFramer

struct RectangleDetectorTests {

    private let detector = RectangleDetector()
    private let size = CGSize(width: 1200, height: 900)

    /// Detected corners must each lie within `tolerance` (fraction of the
    /// image's max dimension) of a distinct ground-truth corner. Matching
    /// is nearest-neighbor so Vision's corner ordering never matters.
    private func expectMatches(
        _ detected: Quad, groundTruth: Quad, imageSize: CGSize, tolerance: CGFloat = 0.025,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let allowed = max(imageSize.width, imageSize.height) * tolerance
        var remaining = groundTruth.perimeterCorners
        for corner in detected.perimeterCorners {
            let distances = remaining.map { candidate in
                ((corner.x - candidate.x) * (corner.x - candidate.x)
                    + (corner.y - candidate.y) * (corner.y - candidate.y)).squareRoot()
            }
            guard let nearest = distances.min(), let index = distances.firstIndex(of: nearest) else {
                Issue.record("no ground-truth corners left", sourceLocation: sourceLocation)
                return
            }
            #expect(
                nearest <= allowed,
                "corner \(corner) is \(nearest) px from nearest ground truth (allowed \(allowed))",
                sourceLocation: sourceLocation
            )
            remaining.remove(at: index)
        }
    }

    @Test func detectsAxisAlignedPicture() async throws {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 150)
        let image = FixtureImageFactory.image(size: size, quad: quad)
        let detected = try #require(try await detector.detectQuad(in: image, fullResolutionSize: size))
        expectMatches(detected, groundTruth: quad, imageSize: size)
    }

    @Test(arguments: [CGFloat(10), 25])
    func detectsRotatedPicture(degrees: CGFloat) async throws {
        let quad = FixtureImageFactory.rotatedQuad(in: size, inset: 250, degrees: degrees)
        let image = FixtureImageFactory.image(size: size, quad: quad)
        let detected = try #require(try await detector.detectQuad(in: image, fullResolutionSize: size))
        expectMatches(detected, groundTruth: quad, imageSize: size, tolerance: 0.035)
    }

    @Test func detectsKeystonedPicture() async throws {
        let quad = FixtureImageFactory.keystonedQuad(in: size, inset: 150, topPinch: 90)
        let image = FixtureImageFactory.image(size: size, quad: quad)
        let detected = try #require(try await detector.detectQuad(in: image, fullResolutionSize: size))
        expectMatches(detected, groundTruth: quad, imageSize: size, tolerance: 0.035)
    }

    @Test func noiseImageReturnsNilInsteadOfThrowing() async throws {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 0xF00D)
        let detected = try await detector.detectQuad(in: image, fullResolutionSize: size)
        #expect(detected == nil)
    }

    @Test func solidImageReturnsNil() async throws {
        let image = FixtureImageFactory.solidImage(size: size)
        let detected = try await detector.detectQuad(in: image, fullResolutionSize: size)
        #expect(detected == nil)
    }

    /// Detecting on a downscaled copy must return corners in FULL-RES
    /// pixels — this is the contract that prevents scale-confusion bugs.
    @Test func downscaledDetectionReturnsFullResolutionQuad() async throws {
        let fullSize = CGSize(width: 4800, height: 3600)
        let quad = FixtureImageFactory.axisAlignedQuad(in: fullSize, inset: 600)
        let fullImage = FixtureImageFactory.image(size: fullSize, quad: quad, frameBorderWidth: 48)
        let small = downscaled(fullImage, maxDimension: 1200)
        #expect(max(small.width, small.height) == 1200)
        let detected = try #require(
            try await detector.detectQuad(in: small, fullResolutionSize: fullSize)
        )
        expectMatches(detected, groundTruth: quad, imageSize: fullSize)
    }

    @Test func widePanoramaDetectedViaPermissiveFallback() async throws {
        let panoramaSize = CGSize(width: 2000, height: 700)
        // Wide, flat picture — aspect ratio beyond the default config.
        let quad = Quad(
            topLeft: CGPoint(x: 200, y: 500),
            topRight: CGPoint(x: 1800, y: 500),
            bottomLeft: CGPoint(x: 200, y: 250),
            bottomRight: CGPoint(x: 1800, y: 250)
        )
        let image = FixtureImageFactory.image(size: panoramaSize, quad: quad)
        let detected = try #require(
            try await detector.detectQuad(in: image, fullResolutionSize: panoramaSize)
        )
        expectMatches(detected, groundTruth: quad, imageSize: panoramaSize, tolerance: 0.035)
    }

    // MARK: downscaled(_:maxDimension:)

    @Test func downscalePreservesAspectRatio() {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 4000, height: 3000))
        let small = downscaled(image, maxDimension: 1000)
        #expect(small.width == 1000)
        #expect(small.height == 750)
    }

    @Test func downscaleNeverUpscales() {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 300, height: 200))
        let same = downscaled(image, maxDimension: 1600)
        #expect(same.width == 300)
        #expect(same.height == 200)
    }
}
