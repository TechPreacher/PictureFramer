import CoreGraphics

/// User-editable repaint mask over the corrected image: an optional
/// detector proposal raster plus ordered brush strokes. Coordinates are
/// canonical (corrected-image pixels, lower-left origin); CGBitmapContext
/// shares that origin, so drawing needs no flip.
struct ReflectionMask: Sendable {

    struct Stroke: Equatable, Sendable {
        enum Mode: Equatable, Sendable { case add, erase }
        var mode: Mode
        /// Brush radius in canonical pixels.
        var radius: CGFloat
        /// Path points in canonical coordinates.
        var points: [CGPoint]
    }

    /// Full-resolution corrected image size the mask refers to.
    let imageSize: CGSize
    /// Grayscale proposal from the detector (white = suspected glare).
    /// May be any resolution; it is scaled to the target on rasterize.
    var detectedRaster: CGImage?
    var strokes: [Stroke]

    init(imageSize: CGSize, detectedRaster: CGImage? = nil, strokes: [Stroke] = []) {
        self.imageSize = imageSize
        self.detectedRaster = detectedRaster
        self.strokes = strokes
    }

    /// True when rasterizing could not produce any repaint pixels.
    var isEmpty: Bool {
        detectedRaster == nil && !strokes.contains { $0.mode == .add }
    }

    mutating func add(_ stroke: Stroke) {
        guard !stroke.points.isEmpty else { return }
        strokes.append(stroke)
    }

    mutating func clear() {
        detectedRaster = nil
        strokes.removeAll()
    }

    /// Renders raster + strokes to a DeviceGray 8-bit image of size
    /// `imageSize * scale`. White = repaint. nil when the mask is empty.
    func rasterize(scale: CGFloat) -> CGImage? {
        guard !isEmpty, scale > 0 else { return nil }
        let width = max(Int((imageSize.width * scale).rounded()), 1)
        let height = max(Int((imageSize.height * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let detectedRaster {
            context.interpolationQuality = .high
            context.draw(detectedRaster, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let gray: CGFloat = stroke.mode == .add ? 1 : 0
            context.setStrokeColor(gray: gray, alpha: 1)
            context.setFillColor(gray: gray, alpha: 1)
            let scaled = stroke.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            let radius = stroke.radius * scale
            if scaled.count == 1, let p = scaled.first {
                context.fillEllipse(in: CGRect(
                    x: p.x - radius, y: p.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            } else {
                context.setLineWidth(radius * 2)
                context.addLines(between: scaled)
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    /// Builds a DeviceGray CGImage from row-major (top row first) bytes.
    /// Shared by the detector and tests.
    static func grayImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard bytes.count == width * height else { return nil }
        var copy = bytes
        return copy.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }
}
