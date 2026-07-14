import CoreImage
import CoreImage.CIFilterBuiltins

/// Wraps CIPerspectiveCorrection. Because canonical space IS Core Image
/// space (pixels, lower-left origin), quad corners pass straight into the
/// filter with no conversion.
struct PerspectiveCorrector: Sendable {

    /// Straightens the region under `quad` — corrects rotation and
    /// horizontal/vertical keystone in one transform. Returns nil for
    /// degenerate input or when rendering fails.
    func correct(
        _ image: CGImage,
        quad: Quad,
        context: RenderContext = .shared
    ) -> CGImage? {
        guard quad.isConvex else { return nil }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = quad.topLeft
        filter.topRight = quad.topRight
        filter.bottomLeft = quad.bottomLeft
        filter.bottomRight = quad.bottomRight
        guard let output = filter.outputImage else { return nil }
        // Move the output extent to the origin so the rendered CGImage
        // starts at (0, 0).
        let translated = output.transformed(
            by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY)
        )
        return context.makeCGImage(from: translated)
    }
}
