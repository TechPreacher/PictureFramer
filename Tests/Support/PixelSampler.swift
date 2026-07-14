import CoreGraphics

/// Reads pixel values from a CGImage for behavioral assertions.
/// Sampling coordinates are canonical (lower-left origin) to match the
/// rest of the app; the flip into row-major bitmap order happens here.
struct PixelSampler {
    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    init(image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// Average of R, G, B in 0...1 at a canonical (lower-left origin) point.
    func grayValue(atCanonical point: CGPoint) -> CGFloat {
        let x = min(max(Int(point.x), 0), width - 1)
        let canonicalY = min(max(Int(point.y), 0), height - 1)
        // CGBitmapContext memory is top-row first; canonical y counts from
        // the bottom.
        let row = height - 1 - canonicalY
        let offset = (row * width + x) * 4
        let r = CGFloat(bytes[offset])
        let g = CGFloat(bytes[offset + 1])
        let b = CGFloat(bytes[offset + 2])
        return (r + g + b) / (3 * 255)
    }

    func isDark(atCanonical point: CGPoint, threshold: CGFloat = 0.4) -> Bool {
        grayValue(atCanonical: point) < threshold
    }

    func isLight(atCanonical point: CGPoint, threshold: CGFloat = 0.6) -> Bool {
        grayValue(atCanonical: point) > threshold
    }
}
