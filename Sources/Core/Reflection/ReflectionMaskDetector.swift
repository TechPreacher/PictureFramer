import CoreGraphics

/// Heuristic glare proposal — no ML, precision-first: it is cheaper for
/// the user to brush a missed reflection than to erase a painting-sized
/// false positive. A pixel counts as glare only when ALL of:
/// - bright in absolute terms (specular highlights wash toward white),
/// - nearly unsaturated (vivid painted color is content, not glare),
/// - locally elevated above its morphological opening (white top-hat) —
///   large uniformly bright regions such as walls or pale painted areas
///   are their own background and cancel out.
/// A minimum blob size rejects speckle, and an optional border band keeps
/// the wall margin of the corrected image out of proposals. The user
/// refines with the brush.
struct ReflectionMaskDetector: Sendable {
    var analysisMaxDimension: CGFloat = 1024
    /// Minimum top-hat response (luminance above local opening) to count.
    var contrastThreshold: Float = 0.08
    /// Absolute luminance floor — glare proposals are near-blown highlights.
    var luminanceFloor: Float = 0.84
    /// Maximum saturation — vivid color is painted content, not glare.
    var saturationCeiling: Float = 0.22
    /// Blobs smaller than this fraction of the analysis image are speckle.
    var minBlobFraction: Double = 0.0003
    var dilationRadius: Int = 2

    /// Grayscale mask at analysis resolution (white = suspected glare),
    /// or nil when nothing qualifies. `border` (in the image's own pixels)
    /// excludes a band around the edges — pass the margin width so the
    /// wall band around the corrected artwork is never proposed.
    func detectMask(in image: CGImage, excludingBorder border: CGFloat = 0) -> CGImage? {
        let small = downscaled(image, maxDimension: analysisMaxDimension)
        let width = small.width
        let height = small.height
        guard width > 2, height > 2 else { return nil }

        guard let (luminance, saturation) = Self.colorPlanes(of: small) else { return nil }

        // Opening window: half-width ~1/16 of the long side — glare
        // structures are narrower than this, walls/content are wider.
        let radius = max(12, max(width, height) / 16)
        let opening = Self.opened(luminance, width: width, height: height, radius: radius)

        var hits = [Bool](repeating: false, count: width * height)
        var hitCount = 0
        for i in 0..<(width * height) {
            if luminance[i] >= luminanceFloor
                && saturation[i] <= saturationCeiling
                && luminance[i] - opening[i] >= contrastThreshold {
                hits[i] = true
                hitCount += 1
            }
        }
        guard hitCount > 0 else { return nil }

        // Border-band exclusion, scaled from source pixels to analysis size.
        if border > 0 {
            let scale = CGFloat(width) / CGFloat(image.width)
            let band = Int((border * scale).rounded())
            if band > 0 {
                for y in 0..<height {
                    for x in 0..<width where hits[y * width + x] {
                        if x < band || x >= width - band || y < band || y >= height - band {
                            hits[y * width + x] = false
                        }
                    }
                }
            }
        }

        let minBlobArea = max(4, Int(Double(width * height) * minBlobFraction))
        Self.removeBlobs(smallerThan: minBlobArea, from: &hits, width: width, height: height)
        guard hits.contains(true) else { return nil }

        // Dilation: generous coverage of halo edges.
        var dilated = [UInt8](repeating: 0, count: width * height)
        let d = dilationRadius
        for y in 0..<height {
            for x in 0..<width where hits[y * width + x] {
                for dy in -d...d {
                    for dx in -d...d {
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

    // MARK: Color planes

    private static func colorPlanes(of image: CGImage) -> (luminance: [Float], saturation: [Float])? {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drew: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        var luminance = [Float](repeating: 0, count: width * height)
        var saturation = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(rgba[i * 4]) / 255
            let g = Float(rgba[i * 4 + 1]) / 255
            let b = Float(rgba[i * 4 + 2]) / 255
            luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let maxC = max(r, g, b)
            saturation[i] = maxC == 0 ? 0 : (maxC - min(r, g, b)) / maxC
        }
        return (luminance, saturation)
    }

    // MARK: Morphological opening (separable box structuring element)

    /// erode (sliding min) then dilate (sliding max), each separable
    /// rows-then-columns.
    private static func opened(
        _ values: [Float], width: Int, height: Int, radius: Int
    ) -> [Float] {
        let eroded = filtered(values, width: width, height: height, radius: radius, takeMin: true)
        return filtered(eroded, width: width, height: height, radius: radius, takeMin: false)
    }

    private static func filtered(
        _ values: [Float], width: Int, height: Int, radius: Int, takeMin: Bool
    ) -> [Float] {
        var pass1 = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            slidingExtremum(
                values, offset: y * width, stride: 1, count: width,
                radius: radius, takeMin: takeMin, into: &pass1
            )
        }
        var pass2 = [Float](repeating: 0, count: values.count)
        for x in 0..<width {
            slidingExtremum(
                pass1, offset: x, stride: width, count: height,
                radius: radius, takeMin: takeMin, into: &pass2
            )
        }
        return pass2
    }

    /// Windowed min/max over [i−radius, i+radius] via a monotonic deque of
    /// indices — every element enters and leaves the deque at most once,
    /// so a full line is O(count) regardless of radius.
    private static func slidingExtremum(
        _ values: [Float], offset: Int, stride: Int, count: Int,
        radius: Int, takeMin: Bool, into output: inout [Float]
    ) {
        var deque = [Int]()
        deque.reserveCapacity(2 * radius + 2)
        var head = 0
        func dominates(_ a: Float, _ b: Float) -> Bool { takeMin ? a <= b : a >= b }
        var next = 0
        for i in 0..<count {
            let windowEnd = min(i + radius, count - 1)
            while next <= windowEnd {
                let value = values[offset + next * stride]
                while deque.count > head, dominates(value, values[offset + deque.last! * stride]) {
                    deque.removeLast()
                }
                deque.append(next)
                next += 1
            }
            while deque[head] < i - radius { head += 1 }
            output[offset + i * stride] = values[offset + deque[head] * stride]
        }
    }

    // MARK: Blob filtering

    /// Flood-fills 4-connected components and clears those below `minArea`.
    private static func removeBlobs(
        smallerThan minArea: Int, from hits: inout [Bool], width: Int, height: Int
    ) {
        var visited = [Bool](repeating: false, count: hits.count)
        var component = [Int]()
        var stack = [Int]()
        for start in 0..<hits.count where hits[start] && !visited[start] {
            component.removeAll(keepingCapacity: true)
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let index = stack.popLast() {
                component.append(index)
                let x = index % width
                let y = index / width
                func push(_ neighbor: Int) {
                    if hits[neighbor] && !visited[neighbor] {
                        visited[neighbor] = true
                        stack.append(neighbor)
                    }
                }
                if x > 0 { push(index - 1) }
                if x < width - 1 { push(index + 1) }
                if y > 0 { push(index - width) }
                if y < height - 1 { push(index + width) }
            }
            if component.count < minArea {
                for index in component { hits[index] = false }
            }
        }
    }
}
