import CoreGraphics

/// A convex quadrilateral in canonical space: source-image pixels with a
/// lower-left origin (identical to Core Image space). "Top" therefore means
/// the larger y coordinate. Every `Quad` in the app stores full-resolution
/// pixel corners; the only y-flip happens in `DisplayMapper`.
struct Quad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    /// Corner identifiers, used by the UI's drag handles.
    enum Corner: CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    subscript(corner: Corner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomLeft: bottomLeft
            case .bottomRight: bottomRight
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomLeft: bottomLeft = newValue
            case .bottomRight: bottomRight = newValue
            }
        }
    }

    /// Corners in perimeter order (counterclockwise in lower-left-origin
    /// space when the quad is upright): tl → tr → br → bl.
    var perimeterCorners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var centroid: CGPoint {
        CGPoint(
            x: (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4,
            y: (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4
        )
    }

    /// True when all cross products of consecutive perimeter edges share a
    /// sign (no reflex corner, no self-intersection through reordering).
    var isConvex: Bool {
        let points = perimeterCorners
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = points[i]
            let b = points[(i + 1) % 4]
            let c = points[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross == 0 { continue }
            if sign == 0 {
                sign = cross
            } else if (cross > 0) != (sign > 0) {
                return false
            }
        }
        return sign != 0
    }

    /// Signed area via the shoelace formula; the sign encodes winding
    /// direction. Used to reject expansion results whose winding flipped
    /// (edges crossed), which stay "convex" by the sign test alone.
    private var signedArea: CGFloat {
        let points = perimeterCorners
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = points[i]
            let b = points[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }

    /// Offsets every edge outward along its outward normal by `margin`
    /// pixels and re-intersects adjacent edge lines. A negative margin
    /// shrinks the quad. Returns nil when adjacent edges are
    /// (near-)parallel, an edge is degenerate, or the result is no longer
    /// convex with the original winding (e.g. a negative margin made edges
    /// cross).
    func expanded(by margin: CGFloat) -> Quad? {
        guard margin != 0 else { return self }
        let center = centroid
        let points = perimeterCorners
        var offsetLines: [LineGeometry.Line] = []
        for i in 0..<4 {
            let a = points[i]
            let b = points[(i + 1) % 4]
            let normal = LineGeometry.outwardNormal(ofEdgeFrom: a, to: b, quadCentroid: center)
            guard normal.dx != 0 || normal.dy != 0 else { return nil }
            offsetLines.append(
                LineGeometry.Line(
                    point: CGPoint(x: a.x + normal.dx * margin, y: a.y + normal.dy * margin),
                    direction: CGVector(dx: b.x - a.x, dy: b.y - a.y)
                )
            )
        }
        // Perimeter corner i is where edge (i-1) meets edge i.
        var newCorners: [CGPoint] = []
        for i in 0..<4 {
            guard let corner = LineGeometry.intersection(offsetLines[(i + 3) % 4], offsetLines[i]) else {
                return nil
            }
            newCorners.append(corner)
        }
        let result = Quad(
            topLeft: newCorners[0],
            topRight: newCorners[1],
            bottomLeft: newCorners[3],
            bottomRight: newCorners[2]
        )
        guard result.isConvex, (result.signedArea > 0) == (signedArea > 0) else { return nil }
        return result
    }

    /// Clamps each corner into `rect`. Used to keep margin-expanded quads
    /// inside the source image so only real pixels are ever sampled.
    func clamped(to rect: CGRect) -> Quad {
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(p.x, rect.minX), rect.maxX),
                y: min(max(p.y, rect.minY), rect.maxY)
            )
        }
        return Quad(
            topLeft: clamp(topLeft),
            topRight: clamp(topRight),
            bottomLeft: clamp(bottomLeft),
            bottomRight: clamp(bottomRight)
        )
    }

    func translated(by offset: CGVector) -> Quad {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.dx, y: p.y + offset.dy) }
        return Quad(
            topLeft: move(topLeft),
            topRight: move(topRight),
            bottomLeft: move(bottomLeft),
            bottomRight: move(bottomRight)
        )
    }

    /// Axis-aligned bounding box of the four corners.
    var boundingBox: CGRect {
        let xs = perimeterCorners.map(\.x)
        let ys = perimeterCorners.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    func scaled(by factor: CGFloat) -> Quad {
        func scale(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * factor, y: p.y * factor) }
        return Quad(
            topLeft: scale(topLeft),
            topRight: scale(topRight),
            bottomLeft: scale(bottomLeft),
            bottomRight: scale(bottomRight)
        )
    }
}
