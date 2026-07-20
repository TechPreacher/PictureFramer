import CoreGraphics
import CoreImage

/// Blends an AI-inpainted patch back into the original so that ONLY
/// masked pixels can change — the fidelity guarantee of the feature.
/// Compositing is pure Core Graphics: where the clip mask is black the
/// framebuffer keeps the already-drawn original bytes untouched.
enum PatchCompositor {

    /// Canonical bounding box of mask pixels > 127. nil for an all-black mask.
    static func maskBoundingBox(of mask: CGImage) -> CGRect? {
        let width = mask.width
        let height = mask.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for x in 0..<width where bytes[row * width + x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Bitmap rows count from the top; canonical y from the bottom.
        let minY = height - 1 - maxRow
        let maxY = height - 1 - minRow
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Gaussian blur of the mask, then zeroed wherever the binary mask is
    /// black — soft edge inside the blob, hard guarantee outside it.
    static func featheredMask(from mask: CGImage, radius: CGFloat) -> CGImage? {
        let width = mask.width
        let height = mask.height
        let blurred = CIImage(cgImage: mask)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        guard let blurredCG = RenderContext.shared.makeCGImage(from: blurred) else { return nil }

        func grayBytes(of image: CGImage) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &bytes, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return bytes
        }
        guard let soft = grayBytes(of: blurredCG), let hard = grayBytes(of: mask) else {
            return nil
        }
        var out = [UInt8](repeating: 0, count: width * height)
        for i in 0..<out.count {
            out[i] = hard[i] > 127 ? soft[i] : 0
        }
        return ReflectionMask.grayImage(from: out, width: width, height: height)
    }

    /// Draws original, clips to the (full-image-sized) grayscale mask —
    /// white = paint — and draws the patch into patchRect. Canonical
    /// coordinates pass straight through: CGBitmapContext is lower-left.
    static func composite(
        original: CGImage,
        patch: CGImage,
        patchRect: CGRect,
        mask: CGImage
    ) -> CGImage? {
        let width = original.width
        let height = original.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: original.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(original, in: fullRect)
        context.saveGState()
        // Grayscale image as clip mask: white samples paint, black are clipped.
        context.clip(to: fullRect, mask: mask)
        context.draw(patch, in: patchRect)
        context.restoreGState()
        return context.makeImage()
    }
}
