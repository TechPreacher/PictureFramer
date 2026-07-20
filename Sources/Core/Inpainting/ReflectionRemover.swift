import CoreGraphics

/// Orchestrates one reflection-removal round trip. The provider only ever
/// sees a padded crop around the mask; the compositor guarantees pixels
/// outside the mask survive unchanged.
struct ReflectionRemover: Sendable {
    /// Context border around the mask bounding box, as a fraction of the
    /// box's larger side — gives the model surrounding artwork to match.
    var paddingFraction: CGFloat = 0.12
    /// Feather radius (full-res pixels) for the composite seam.
    var featherRadius: CGFloat = 6

    func remove(
        from image: CGImage,
        mask: ReflectionMask,
        provider: any InpaintingProvider,
        apiKey: String
    ) async throws -> CGImage {
        guard let fullMask = mask.rasterize(scale: 1),
              fullMask.width == image.width, fullMask.height == image.height else {
            throw InpaintingError.emptyMask
        }
        guard let box = PatchCompositor.maskBoundingBox(of: fullMask) else {
            throw InpaintingError.emptyMask
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let padding = max(box.width, box.height) * paddingFraction
        let cropRect = box.insetBy(dx: -padding, dy: -padding)
            .intersection(bounds)
            .integral
            .intersection(bounds)
        guard cropRect.width >= 1, cropRect.height >= 1,
              let imageCrop = croppedCanonical(image, to: cropRect),
              let maskCrop = croppedCanonical(fullMask, to: cropRect) else {
            throw InpaintingError.renderingFailed
        }

        let uploadSize = provider.uploadSize(for: cropRect.size)
        guard let uploadImage = resized(imageCrop, to: uploadSize),
              let uploadMask = resized(maskCrop, to: uploadSize) else {
            throw InpaintingError.renderingFailed
        }

        let patch = try await provider.inpaint(
            image: uploadImage, mask: uploadMask, apiKey: apiKey)

        // Resize back to the crop rect — any aspect distortion from the
        // upload resize cancels here.
        guard let patchAtCropSize = resized(patch, to: cropRect.size),
              let feathered = PatchCompositor.featheredMask(
                  from: fullMask, radius: featherRadius),
              let result = PatchCompositor.composite(
                  original: image,
                  patch: patchAtCropSize,
                  patchRect: cropRect,
                  mask: feathered) else {
            throw InpaintingError.renderingFailed
        }
        return result
    }
}
