import CoreGraphics
@testable import PictureFramer

/// Renders deterministic synthetic test images headlessly — no bundled
/// assets. CGBitmapContext uses a lower-left origin, matching canonical
/// space, so `Quad` corners are drawn verbatim with no flip.
enum FixtureImageFactory {

    /// A filled quadrilateral (the "framed picture") with a lighter frame
    /// border, on a contrasting background.
    static func image(
        size: CGSize,
        backgroundGray: CGFloat = 0.85,
        quad: Quad,
        fillGray: CGFloat = 0.15,
        frameBorderWidth: CGFloat = 12
    ) -> CGImage {
        drawImage(size: size) { context in
            context.setFillColor(gray: backgroundGray, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))

            let path = CGMutablePath()
            path.addLines(between: quad.perimeterCorners)
            path.closeSubpath()

            context.setFillColor(gray: fillGray, alpha: 1)
            context.addPath(path)
            context.fillPath()

            // Lighter "frame" stroke for realistic high-contrast edges.
            context.setStrokeColor(gray: 0.45, alpha: 1)
            context.setLineWidth(frameBorderWidth)
            context.addPath(path)
            context.strokePath()
        }
    }

    /// Deterministic pseudo-random noise — contains no rectangle.
    static func noiseImage(size: CGSize, seed: UInt64) -> CGImage {
        var state = seed
        func nextGray() -> CGFloat {
            // xorshift64 — deterministic across runs and platforms.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 256) / 255
        }
        let cell: CGFloat = 8
        return drawImage(size: size) { context in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.setFillColor(gray: nextGray(), alpha: 1)
                    context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell
                }
                y += cell
            }
        }
    }

    static func solidImage(size: CGSize, gray: CGFloat = 0.5) -> CGImage {
        drawImage(size: size) { context in
            context.setFillColor(gray: gray, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Ground-truth quads

    static func axisAlignedQuad(in size: CGSize, inset: CGFloat) -> Quad {
        Quad(
            topLeft: CGPoint(x: inset, y: size.height - inset),
            topRight: CGPoint(x: size.width - inset, y: size.height - inset),
            bottomLeft: CGPoint(x: inset, y: inset),
            bottomRight: CGPoint(x: size.width - inset, y: inset)
        )
    }

    static func rotatedQuad(in size: CGSize, inset: CGFloat, degrees: CGFloat) -> Quad {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radians = degrees * .pi / 180
        let base = axisAlignedQuad(in: size, inset: inset)
        func rotate(_ p: CGPoint) -> CGPoint {
            let dx = p.x - center.x
            let dy = p.y - center.y
            return CGPoint(
                x: center.x + dx * cos(radians) - dy * sin(radians),
                y: center.y + dx * sin(radians) + dy * cos(radians)
            )
        }
        return Quad(
            topLeft: rotate(base.topLeft),
            topRight: rotate(base.topRight),
            bottomLeft: rotate(base.bottomLeft),
            bottomRight: rotate(base.bottomRight)
        )
    }

    /// Trapezoid with the top edge pinched inward by `topPinch` per side —
    /// simulates vertical keystone (photographed from below).
    static func keystonedQuad(in size: CGSize, inset: CGFloat, topPinch: CGFloat) -> Quad {
        var quad = axisAlignedQuad(in: size, inset: inset)
        quad.topLeft.x += topPinch
        quad.topRight.x -= topPinch
        return quad
    }

    // MARK: Drawing

    private static func drawImage(size: CGSize, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        return context.makeImage()!
    }
}
