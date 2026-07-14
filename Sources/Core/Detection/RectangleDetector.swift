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

    /// Runs rectangle detection on `image` and returns the best observation
    /// as a quad scaled to `fullResolutionSize`, or nil when nothing is
    /// found. Tries `configuration` first, then the permissive fallback.
    func detectQuad(
        in image: CGImage,
        fullResolutionSize: CGSize,
        configuration: Configuration = .default
    ) async throws -> Quad? {
        if let quad = try await runRequest(on: image, fullResolutionSize: fullResolutionSize, configuration: configuration) {
            return quad
        }
        return try await runRequest(
            on: image,
            fullResolutionSize: fullResolutionSize,
            configuration: .permissiveFallback
        )
    }

    private func runRequest(
        on image: CGImage,
        fullResolutionSize: CGSize,
        configuration: Configuration
    ) async throws -> Quad? {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = configuration.minimumSize
        request.minimumAspectRatio = configuration.minimumAspectRatio
        request.maximumAspectRatio = configuration.maximumAspectRatio
        request.minimumConfidence = configuration.minimumConfidence
        request.quadratureTolerance = configuration.quadratureTolerance
        request.maximumObservations = 5

        // VNImageRequestHandler.perform is synchronous; hop off the caller.
        let observations: [VNRectangleObservation] = try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            return request.results ?? []
        }.value

        guard let best = pickBest(from: observations) else { return nil }
        return VisionQuadConversion.quad(
            fromNormalized: VisionQuadConversion.NormalizedCorners(
                topLeft: best.topLeft,
                topRight: best.topRight,
                bottomLeft: best.bottomLeft,
                bottomRight: best.bottomRight
            ),
            imagePixelSize: fullResolutionSize
        )
    }

    /// Highest confidence wins; area breaks ties so the outer frame edge
    /// beats an inner mat/canvas edge of equal confidence.
    private func pickBest(from observations: [VNRectangleObservation]) -> VNRectangleObservation? {
        observations.max { a, b in
            if a.confidence != b.confidence { return a.confidence < b.confidence }
            return normalizedArea(a) < normalizedArea(b)
        }
    }

    private func normalizedArea(_ observation: VNRectangleObservation) -> CGFloat {
        observation.boundingBox.width * observation.boundingBox.height
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
