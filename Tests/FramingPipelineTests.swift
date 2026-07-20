import CoreGraphics
import Foundation
import Testing
@testable import PictureFramer

struct FramingPipelineTests {

    private let pipeline = FramingPipeline()
    private let size = CGSize(width: 2400, height: 1800)

    @Test func endToEndDetectAndStraighten() async throws {
        let quad = FixtureImageFactory.keystonedQuad(in: size, inset: 300, topPinch: 150)
        let image = FixtureImageFactory.image(size: size, quad: quad, frameBorderWidth: 24)

        let detected = try #require(try await pipeline.detectQuad(in: image))

        let tight = try #require(pipeline.finalImage(fullResImage: image, quad: detected, marginPixels: 0))
        let withMargin = try #require(pipeline.finalImage(fullResImage: image, quad: detected, marginPixels: 40))

        // Margin grows the output (~80 px per dimension, loose bounds for
        // homography rescaling).
        #expect(withMargin.width - tight.width > 40)
        #expect(withMargin.width - tight.width < 160)
        #expect(withMargin.height - tight.height > 40)
        #expect(withMargin.height - tight.height < 160)

        // Straightened picture fills the tight crop; margin band is real
        // background in the margin crop.
        let tightSampler = PixelSampler(image: tight)
        #expect(tightSampler.isDark(atCanonical: CGPoint(x: CGFloat(tight.width) / 2, y: CGFloat(tight.height) / 2)))

        let marginSampler = PixelSampler(image: withMargin)
        let w = CGFloat(withMargin.width)
        let h = CGFloat(withMargin.height)
        #expect(marginSampler.isLight(atCanonical: CGPoint(x: w / 2, y: 12)))
        #expect(marginSampler.isLight(atCanonical: CGPoint(x: 12, y: h / 2)))
        #expect(marginSampler.isDark(atCanonical: CGPoint(x: w / 2, y: h / 2)))
    }

    @Test func effectiveQuadClampsOversizedMargin() {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 100)
        let effective = pipeline.effectiveQuad(from: quad, marginPixels: 5000, imageSize: size)
        let bounds = CGRect(origin: .zero, size: size)
        for corner in effective.perimeterCorners {
            #expect(corner.x >= bounds.minX && corner.x <= bounds.maxX)
            #expect(corner.y >= bounds.minY && corner.y <= bounds.maxY)
        }
        #expect(effective.isConvex)
    }

    @Test func effectiveQuadZeroMarginIsIdentityForInBoundsQuad() {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 100)
        #expect(pipeline.effectiveQuad(from: quad, marginPixels: 0, imageSize: size) == quad)
    }

    @Test func effectiveQuadFallsBackWhenExpansionDegenerates() {
        // Collinear corners: expansion returns nil → clamped original.
        let degenerate = Quad(
            topLeft: CGPoint(x: 0, y: 500),
            topRight: CGPoint(x: 1000, y: 500),
            bottomLeft: CGPoint(x: 2000, y: 500),
            bottomRight: CGPoint(x: 3000, y: 500)
        )
        let result = pipeline.effectiveQuad(from: degenerate, marginPixels: 50, imageSize: size)
        #expect(result == degenerate.clamped(to: CGRect(origin: .zero, size: size)))
    }

    @Test func previewAndFinalAgreeOnAspectRatio() async throws {
        let quad = FixtureImageFactory.keystonedQuad(in: size, inset: 300, topPinch: 120)
        let image = FixtureImageFactory.image(size: size, quad: quad, frameBorderWidth: 24)

        let preview = try #require(
            pipeline.previewImage(fullResImage: image, quad: quad, marginPixels: 60, maxDimension: 800)
        )
        let final = try #require(pipeline.finalImage(fullResImage: image, quad: quad, marginPixels: 60))

        #expect(preview.width < final.width)  // preview really is downscaled
        let previewAspect = CGFloat(preview.width) / CGFloat(preview.height)
        let finalAspect = CGFloat(final.width) / CGFloat(final.height)
        #expect(abs(previewAspect - finalAspect) / finalAspect < 0.02)
    }

    @Test func cachedBasePreviewMatchesFullResPath() throws {
        let quad = FixtureImageFactory.keystonedQuad(in: size, inset: 300, topPinch: 120)
        let image = FixtureImageFactory.image(size: size, quad: quad, frameBorderWidth: 24)

        let viaFullRes = try #require(
            pipeline.previewImage(fullResImage: image, quad: quad, marginPixels: 60, maxDimension: 800)
        )
        let base = downscaled(image, maxDimension: 800)
        let viaCachedBase = try #require(
            pipeline.previewImage(
                downscaled: base,
                scaleFromFullRes: CGFloat(base.width) / size.width,
                quad: quad,
                marginPixels: 60
            )
        )
        #expect(viaCachedBase.width == viaFullRes.width)
        #expect(viaCachedBase.height == viaFullRes.height)
    }

    @Test func cachedBasePreviewRejectsZeroScale() {
        let base = FixtureImageFactory.solidImage(size: CGSize(width: 100, height: 100))
        let quad = FixtureImageFactory.axisAlignedQuad(in: CGSize(width: 100, height: 100), inset: 10)
        #expect(pipeline.previewImage(downscaled: base, scaleFromFullRes: 0, quad: quad, marginPixels: 10) == nil)
    }

    @Test func panShiftsCropWithoutDeformingIt() {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 300)
        let panned = pipeline.effectiveQuad(
            from: quad, marginPixels: 0, imageSize: size,
            panOffset: CGVector(dx: 120, dy: -80)
        )
        #expect(panned == quad.translated(by: CGVector(dx: 120, dy: -80)))
    }

    @Test func panIsClampedToImageBounds() {
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 300)
        let panned = pipeline.effectiveQuad(
            from: quad, marginPixels: 0, imageSize: size,
            panOffset: CGVector(dx: 100_000, dy: 100_000)
        )
        // Slid to the top-right image edge, shape intact (300 px of slack).
        #expect(panned == quad.translated(by: CGVector(dx: 300, dy: 300)))
        let bounds = CGRect(origin: .zero, size: size)
        for corner in panned.perimeterCorners {
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(corner))
        }
    }

    @Test func quadWiderThanImageDoesNotPanHorizontally() {
        // Bounding box wider than the image → x pan pinned to zero.
        let quad = Quad(
            topLeft: CGPoint(x: -100, y: 1500),
            topRight: CGPoint(x: 2500, y: 1500),
            bottomLeft: CGPoint(x: -100, y: 300),
            bottomRight: CGPoint(x: 2500, y: 300)
        )
        let pan = FramingPipeline.clampedPan(
            CGVector(dx: 500, dy: 0), for: quad, in: CGRect(origin: .zero, size: size)
        )
        #expect(pan == CGVector(dx: 0, dy: 0))
    }

    @Test func pannedFinalImageShowsBackgroundOnTheVacatedSide() throws {
        // Dark painting with 200 px of light wall around it. Panning the
        // crop right by 150 px should pull light background into the right
        // edge of the output while the left edge stays inside the painting.
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 200)
        let image = FixtureImageFactory.image(size: size, quad: quad, frameBorderWidth: 24)

        let panned = try #require(
            pipeline.finalImage(
                fullResImage: image, quad: quad, marginPixels: 0,
                panOffset: CGVector(dx: 150, dy: 0)
            )
        )
        let sampler = PixelSampler(image: panned)
        let w = CGFloat(panned.width)
        let h = CGFloat(panned.height)
        #expect(sampler.isLight(atCanonical: CGPoint(x: w - 40, y: h / 2)), "vacated side should be wall")
        #expect(sampler.isDark(atCanonical: CGPoint(x: 40, y: h / 2)), "opposite side should be painting")
    }

    @Test func tinyImageBelowDownscaleTargetStillDetects() async throws {
        let tinySize = CGSize(width: 320, height: 240)
        let quad = FixtureImageFactory.axisAlignedQuad(in: tinySize, inset: 40)
        let image = FixtureImageFactory.image(size: tinySize, quad: quad, frameBorderWidth: 4)
        let detected = try await pipeline.detectQuad(in: image)
        #expect(detected != nil)
    }

    @Test func onePixelImageFailsGracefully() async throws {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 1, height: 1))
        let detected = try await pipeline.detectQuad(in: image)
        #expect(detected == nil)
        let quad = Quad(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomLeft: .zero,
            bottomRight: CGPoint(x: 1, y: 0)
        )
        // Rendering a 1×1 crop should not crash; nil or a tiny image are
        // both acceptable.
        _ = pipeline.finalImage(fullResImage: image, quad: quad, marginPixels: 10)
    }

    @Test func detectQuadForwardsPaintingOnlyMode() async throws {
        let size = CGSize(width: 1200, height: 900)
        let outer = FixtureImageFactory.axisAlignedQuad(in: size, inset: 150)
        let inner = try #require(outer.expanded(by: -120))
        let image = FixtureImageFactory.framedPaintingImage(
            size: size, outerQuad: outer, innerQuad: inner)
        let detected = try #require(
            try await FramingPipeline().detectQuad(in: image, mode: .paintingOnly))
        // Painting mode must land on the inner quad, not the frame. Vision
        // is not pixel-exact; assert each corner within 3.5% of max dim.
        let allowed = max(size.width, size.height) * 0.035
        for corner in detected.perimeterCorners {
            let nearest = inner.perimeterCorners
                .map { hypot(corner.x - $0.x, corner.y - $0.y) }
                .min()!
            #expect(nearest <= allowed)
        }
    }
}
