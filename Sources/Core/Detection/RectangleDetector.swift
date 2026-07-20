import CoreGraphics
import Vision

/// Detects the outer quadrilateral of a framed picture using Vision.
/// Callers may pass a downscaled image for speed; the returned `Quad` is
/// always in canonical full-resolution pixel space.
struct RectangleDetector: Sendable {

    struct Configuration: Sendable {
        var minimumSize: Float
        var minimumAspectRatio: Float
        var maximumAspectRatio: Float
        var minimumConfidence: Float
        var quadratureTolerance: Float

        /// Tuned for a large framed picture filling most of the photo.
        static let `default` = Configuration(
            minimumSize: 0.3,
            minimumAspectRatio: 0.2,
            maximumAspectRatio: 1.0,
            minimumConfidence: 0.6,
            quadratureTolerance: 30
        )

        /// Second pass when the default finds nothing — small or extreme
        /// aspect-ratio pictures, low-contrast frames.
        static let permissiveFallback = Configuration(
            minimumSize: 0.15,
            minimumAspectRatio: 0.05,
            maximumAspectRatio: 1.0,
            minimumConfidence: 0.3,
            quadratureTolerance: 45
        )
    }

    /// A converted Vision observation: full-res canonical quad + confidence.
    struct Candidate: Equatable, Sendable {
        var quad: Quad
        var confidence: Float
    }

    /// Fraction of the image's max dimension a nested candidate must sit
    /// inside the outer candidate's bounding box — rejects Vision
    /// near-duplicate detections of the same physical edge.
    private static let nestedInsetFraction: CGFloat = 0.015

    /// Runs rectangle detection on `image` and returns the quad for `mode`,
    /// scaled to `fullResolutionSize`, or nil when nothing is found.
    /// Framed mode: best observation (confidence, then area) — unchanged
    /// behavior. Painting-only mode: largest candidate nested inside the
    /// outer one; falls back to the outer quad so the user can still adjust
    /// corners manually when Vision only sees the frame.
    func detectQuad(
        in image: CGImage,
        fullResolutionSize: CGSize,
        mode: CropMode = .framed,
        configuration: Configuration = .default
    ) async throws -> Quad? {
        let first = try await candidateQuads(
            on: image, fullResolutionSize: fullResolutionSize, configuration: configuration)
        switch mode {
        case .framed:
            if let best = Self.bestOuterQuad(from: first) { return best }
            let second = try await candidateQuads(
                on: image, fullResolutionSize: fullResolutionSize,
                configuration: .permissiveFallback)
            return Self.bestOuterQuad(from: second)
        case .paintingOnly:
            if let nested = Self.nestedQuad(from: first, imageSize: fullResolutionSize) {
                return nested
            }
            // The permissive pass may see the lower-contrast inner edge the
            // default pass missed; combine so the outer frame from pass one
            // still anchors the nesting check.
            let second = try await candidateQuads(
                on: image, fullResolutionSize: fullResolutionSize,
                configuration: .permissiveFallback)
            let combined = first + second
            if let nested = Self.nestedQuad(from: combined, imageSize: fullResolutionSize) {
                return nested
            }
            return Self.bestOuterQuad(from: combined)
        }
    }

    private func candidateQuads(
        on image: CGImage,
        fullResolutionSize: CGSize,
        configuration: Configuration
    ) async throws -> [Candidate] {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = configuration.minimumSize
        request.minimumAspectRatio = configuration.minimumAspectRatio
        request.maximumAspectRatio = configuration.maximumAspectRatio
        request.minimumConfidence = configuration.minimumConfidence
        request.quadratureTolerance = configuration.quadratureTolerance
        request.maximumObservations = 8

        // VNImageRequestHandler.perform is synchronous; hop off the caller.
        let observations: [VNRectangleObservation] = try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            return request.results ?? []
        }.value

        return observations.map { observation in
            Candidate(
                quad: VisionQuadConversion.quad(
                    fromNormalized: VisionQuadConversion.NormalizedCorners(
                        topLeft: observation.topLeft,
                        topRight: observation.topRight,
                        bottomLeft: observation.bottomLeft,
                        bottomRight: observation.bottomRight
                    ),
                    imagePixelSize: fullResolutionSize
                ),
                confidence: observation.confidence
            )
        }
    }

    /// Highest confidence wins; area breaks ties so the outer frame edge
    /// beats an inner mat/canvas edge of equal confidence.
    static func bestOuterQuad(from candidates: [Candidate]) -> Quad? {
        candidates.max { a, b in
            if a.confidence != b.confidence { return a.confidence < b.confidence }
            return area(a.quad) < area(b.quad)
        }?.quad
    }

    /// The painting inside the frame: the largest candidate whose corners
    /// all sit inside the outer candidate's bounding box by at least the
    /// nested inset. Nil when no candidate is genuinely nested.
    static func nestedQuad(from candidates: [Candidate], imageSize: CGSize) -> Quad? {
        guard let outer = bestOuterQuad(from: candidates) else { return nil }
        let inset = Self.nestedInsetFraction * max(imageSize.width, imageSize.height)
        let container = outer.boundingBox.insetBy(dx: inset, dy: inset)
        return candidates
            .filter { candidate in
                candidate.quad != outer
                    && candidate.quad.perimeterCorners.allSatisfy(container.contains)
            }
            .max { area($0.quad) < area($1.quad) }?
            .quad
    }

    private static func area(_ quad: Quad) -> CGFloat {
        quad.boundingBox.width * quad.boundingBox.height
    }
}

/// Draws `image` into a smaller bitmap so detection and previews stay fast.
/// Never upscales.
func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let largest = max(width, height)
    guard largest > maxDimension else { return image }
    let scale = maxDimension / largest
    let newWidth = max(Int(width * scale), 1)
    let newHeight = max(Int(height * scale), 1)
    guard let context = CGContext(
        data: nil,
        width: newWidth,
        height: newHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    return context.makeImage() ?? image
}
