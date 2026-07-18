import CoreGraphics

/// Heuristic glare proposal — no ML. A pixel is "glare" when it is bright
/// AND nearly unsaturated (specular highlights wash out color). The blob
/// map is dilated so the proposal generously covers halo edges; the user
/// refines with the brush afterwards.
struct ReflectionMaskDetector: Sendable {
    var analysisMaxDimension: CGFloat = 1024
    var luminanceThreshold: CGFloat = 0.82
    var saturationThreshold: CGFloat = 0.30
    var dilationRadius: Int = 2

    /// Grayscale mask at analysis resolution (white = suspected glare),
    /// or nil when no pixel qualifies.
    func detectMask(in image: CGImage) -> CGImage? {
        let small = downscaled(image, maxDimension: analysisMaxDimension)
        let width = small.width
        let height = small.height
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hits = [Bool](repeating: false, count: width * height)
        var hitCount = 0
        for i in 0..<(width * height) {
            let r = CGFloat(rgba[i * 4]) / 255
            let g = CGFloat(rgba[i * 4 + 1]) / 255
            let b = CGFloat(rgba[i * 4 + 2]) / 255
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let maxC = max(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - min(r, g, b)) / maxC
            if luminance >= luminanceThreshold && saturation <= saturationThreshold {
                hits[i] = true
                hitCount += 1
            }
        }
        guard hitCount > 0 else { return nil }

        // Box dilation: generous coverage of halo edges.
        var dilated = [UInt8](repeating: 0, count: width * height)
        let radius = dilationRadius
        for y in 0..<height {
            for x in 0..<width where hits[y * width + x] {
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx
                        let ny = y + dy
                        if nx >= 0, nx < width, ny >= 0, ny < height {
                            dilated[ny * width + nx] = 255
                        }
                    }
                }
            }
        }
        return ReflectionMask.grayImage(from: dilated, width: width, height: height)
    }
}
