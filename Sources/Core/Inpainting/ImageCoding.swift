import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func pngData(from image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

func cgImage(fromEncoded data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Non-uniform resize. Callers that distort aspect always resize back to
/// the source rect afterwards, so the distortion cancels.
func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
    let width = max(Int(size.width.rounded()), 1)
    let height = max(Int(size.height.rounded()), 1)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// Crop with a canonical (lower-left origin) rect. CGImage.cropping takes
/// a top-left-origin rect — this wrapper is the only place that flip
/// happens for crops.
func croppedCanonical(_ image: CGImage, to rect: CGRect) -> CGImage? {
    let flipped = CGRect(
        x: rect.minX,
        y: CGFloat(image.height) - rect.maxY,
        width: rect.width,
        height: rect.height
    )
    return image.cropping(to: flipped)
}
