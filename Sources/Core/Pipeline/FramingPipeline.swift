import CoreGraphics

/// Composes detection → margin expansion → perspective correction.
/// Detection and previews run on downscaled copies for speed; the final
/// export always applies the transform to the original full-resolution
/// pixels.
struct FramingPipeline: Sendable {
    var detector = RectangleDetector()
    var corrector = PerspectiveCorrector()

    /// Max dimension of the copy used for detection.
    var detectionMaxDimension: CGFloat = 1600

    /// Detects the picture's outer quad. Runs Vision on a downscaled copy;
    /// the returned quad is in full-resolution canonical pixels.
    func detectQuad(in fullResImage: CGImage) async throws -> Quad? {
        let fullSize = CGSize(width: fullResImage.width, height: fullResImage.height)
        guard fullSize.width >= 2, fullSize.height >= 2 else { return nil }
        let small = downscaled(fullResImage, maxDimension: detectionMaxDimension)
        return try await detector.detectQuad(in: small, fullResolutionSize: fullSize)
    }

    /// The quad that will actually be cropped: expanded outward by
    /// `marginPixels` in source space, shifted by `panOffset` (recenters
    /// the crop when a shadow skewed detection), clamped to the image so
    /// only real pixels are sampled. Falls back to the unexpanded quad
    /// when expansion degenerates.
    func effectiveQuad(
        from quad: Quad,
        marginPixels: CGFloat,
        imageSize: CGSize,
        panOffset: CGVector = .zero
    ) -> Quad {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let expanded = quad.expanded(by: marginPixels) ?? quad
        let pan = Self.clampedPan(panOffset, for: expanded, in: bounds)
        return expanded.translated(by: pan).clamped(to: bounds)
    }

    /// Limits a pan so the quad's bounding box stays inside `bounds` —
    /// panning slides the crop window without deforming it. When the box
    /// is already wider/taller than the image, that axis doesn't pan.
    static func clampedPan(_ offset: CGVector, for quad: Quad, in bounds: CGRect) -> CGVector {
        let box = quad.boundingBox
        func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            lo > hi ? 0 : min(max(value, lo), hi)
        }
        return CGVector(
            dx: clamp(offset.dx, bounds.minX - box.minX, bounds.maxX - box.maxX),
            dy: clamp(offset.dy, bounds.minY - box.minY, bounds.maxY - box.maxY)
        )
    }

    /// Fast path for interactive preview: corrects a downscaled copy.
    /// The quad and margin are given in full-res pixels and scaled down to
    /// match the preview copy.
    func previewImage(
        fullResImage: CGImage,
        quad: Quad,
        marginPixels: CGFloat,
        maxDimension: CGFloat = 1600
    ) -> CGImage? {
        let fullSize = CGSize(width: fullResImage.width, height: fullResImage.height)
        guard fullSize.width >= 1, fullSize.height >= 1 else { return nil }
        let small = downscaled(fullResImage, maxDimension: maxDimension)
        return previewImage(
            downscaled: small,
            scaleFromFullRes: CGFloat(small.width) / fullSize.width,
            quad: quad,
            marginPixels: marginPixels
        )
    }

    /// Preview from an already-downscaled copy — callers that re-render
    /// interactively (margin slider, corner drags) downscale once and pass
    /// the cached copy here instead of paying the downscale per frame.
    func previewImage(
        downscaled small: CGImage,
        scaleFromFullRes scale: CGFloat,
        quad: Quad,
        marginPixels: CGFloat,
        panOffset: CGVector = .zero
    ) -> CGImage? {
        guard scale > 0 else { return nil }
        let smallSize = CGSize(width: small.width, height: small.height)
        let scaledQuad = effectiveQuad(
            from: quad.scaled(by: scale),
            marginPixels: marginPixels * scale,
            imageSize: smallSize,
            panOffset: CGVector(dx: panOffset.dx * scale, dy: panOffset.dy * scale)
        )
        return corrector.correct(small, quad: scaledQuad)
    }

    /// Export path: applies margin + correction to the ORIGINAL pixels.
    func finalImage(
        fullResImage: CGImage,
        quad: Quad,
        marginPixels: CGFloat,
        panOffset: CGVector = .zero
    ) -> CGImage? {
        let fullSize = CGSize(width: fullResImage.width, height: fullResImage.height)
        guard fullSize.width >= 1, fullSize.height >= 1 else { return nil }
        let effective = effectiveQuad(
            from: quad,
            marginPixels: marginPixels,
            imageSize: fullSize,
            panOffset: panOffset
        )
        return corrector.correct(fullResImage, quad: effective)
    }
}
