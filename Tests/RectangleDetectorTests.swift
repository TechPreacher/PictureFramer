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

    // MARK: Mode-aware selection (pure logic, no Vision)

    private var nestedFixtureQuads: (outer: Quad, inner: Quad) {
        let outer = FixtureImageFactory.axisAlignedQuad(in: size, inset: 150)
        // Negative expansion shrinks — 120 px frame width on every side.
        let inner = outer.expanded(by: -120)!
        return (outer, inner)
    }

    @Test func nestedSelectionPicksInnerCandidate() {
        let (outer, inner) = nestedFixtureQuads
        let candidates = [
            RectangleDetector.Candidate(quad: outer, confidence: 0.9),
            RectangleDetector.Candidate(quad: inner, confidence: 0.8),
        ]
        #expect(RectangleDetector.nestedQuad(from: candidates, imageSize: size) == inner)
    }

    /// Vision often reports the same physical edge twice with tiny offsets.
    /// A near-duplicate of the outer quad must not count as "nested".
    @Test func nearDuplicateOfOuterIsNotNested() {
        let (outer, _) = nestedFixtureQuads
        let duplicate = outer.expanded(by: -5)!  // 5 px < 1.5% inset (18 px)
        let candidates = [
            RectangleDetector.Candidate(quad: outer, confidence: 0.9),
            RectangleDetector.Candidate(quad: duplicate, confidence: 0.85),
        ]
        #expect(RectangleDetector.nestedQuad(from: candidates, imageSize: size) == nil)
    }

    /// Several nested rectangles (painting, then artwork detail inside it):
    /// the largest nested one is the painting.
    @Test func largestNestedCandidateWins() {
        let (outer, inner) = nestedFixtureQuads
        let detail = outer.expanded(by: -250)!
        let candidates = [
            RectangleDetector.Candidate(quad: outer, confidence: 0.9),
            RectangleDetector.Candidate(quad: detail, confidence: 0.9),
            RectangleDetector.Candidate(quad: inner, confidence: 0.7),
        ]
        #expect(RectangleDetector.nestedQuad(from: candidates, imageSize: size) == inner)
    }

    @Test func noCandidatesYieldsNoNestedQuad() {
        #expect(RectangleDetector.nestedQuad(from: [], imageSize: size) == nil)
    }

    @Test func bestOuterPrefersConfidenceThenArea() {
        let (outer, inner) = nestedFixtureQuads
        let equalConfidence = [
            RectangleDetector.Candidate(quad: inner, confidence: 0.9),
            RectangleDetector.Candidate(quad: outer, confidence: 0.9),
        ]
        #expect(RectangleDetector.bestOuterQuad(from: equalConfidence) == outer)
        let higherConfidenceInner = [
            RectangleDetector.Candidate(quad: inner, confidence: 0.95),
            RectangleDetector.Candidate(quad: outer, confidence: 0.9),
        ]
        #expect(RectangleDetector.bestOuterQuad(from: higherConfidenceInner) == inner)
    }

    // MARK: Painting-only mode (end-to-end Vision)

    @Test func paintingModeDetectsInnerPainting() async throws {
        let (outer, inner) = nestedFixtureQuads
        let image = FixtureImageFactory.framedPaintingImage(
            size: size, outerQuad: outer, innerQuad: inner)
        let detected = try #require(
            try await detector.detectQuad(
                in: image, fullResolutionSize: size, mode: .paintingOnly))
        expectMatches(detected, groundTruth: inner, imageSize: size, tolerance: 0.035)
    }

    @Test func framedModeStillDetectsOuterFrameOnNestedFixture() async throws {
        let (outer, inner) = nestedFixtureQuads
        let image = FixtureImageFactory.framedPaintingImage(
            size: size, outerQuad: outer, innerQuad: inner)
        let detected = try #require(
            try await detector.detectQuad(
                in: image, fullResolutionSize: size, mode: .framed))
        expectMatches(detected, groundTruth: outer, imageSize: size, tolerance: 0.035)
    }

    /// A fixture with only one rectangle: painting mode has nothing nested
    /// and must fall back to the outer quad, not fail.
    @Test func paintingModeFallsBackToOuterQuadWhenNothingNested() async throws {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 150)
        let image = FixtureImageFactory.image(size: size, quad: quad)
        let detected = try #require(
            try await detector.detectQuad(
                in: image, fullResolutionSize: size, mode: .paintingOnly))
        expectMatches(detected, groundTruth: quad, imageSize: size, tolerance: 0.035)
    }
}
