import CoreGraphics

/// Pure 2-D line math used by `Quad` expansion. No framework dependencies
/// beyond CoreGraphics value types.
enum LineGeometry {

    /// An infinite line through `point` with (not necessarily normalized)
    /// `direction`.
    struct Line {
        var point: CGPoint
        var direction: CGVector
    }

    private static let parallelEpsilon: CGFloat = 1e-9

    /// Intersection of two infinite lines, or nil when they are
    /// (near-)parallel.
    static func intersection(_ a: Line, _ b: Line) -> CGPoint? {
        let cross = a.direction.dx * b.direction.dy - a.direction.dy * b.direction.dx
        guard abs(cross) > parallelEpsilon else { return nil }
        let dx = b.point.x - a.point.x
        let dy = b.point.y - a.point.y
        let t = (dx * b.direction.dy - dy * b.direction.dx) / cross
        return CGPoint(
            x: a.point.x + t * a.direction.dx,
            y: a.point.y + t * a.direction.dy
        )
    }

    /// Unit normal of the edge a→b that points away from `quadCentroid`.
    /// Checking against the centroid makes the result independent of the
    /// quad's winding order. Returns .zero for a degenerate (zero-length)
    /// edge.
    static func outwardNormal(
        ofEdgeFrom a: CGPoint,
        to b: CGPoint,
        quadCentroid centroid: CGPoint
    ) -> CGVector {
        let edge = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let length = (edge.dx * edge.dx + edge.dy * edge.dy).squareRoot()
        guard length > 0 else { return CGVector(dx: 0, dy: 0) }
        var normal = CGVector(dx: edge.dy / length, dy: -edge.dx / length)
        let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let towardCentroid = CGVector(dx: centroid.x - midpoint.x, dy: centroid.y - midpoint.y)
        if normal.dx * towardCentroid.dx + normal.dy * towardCentroid.dy > 0 {
            normal = CGVector(dx: -normal.dx, dy: -normal.dy)
        }
        return normal
    }
}
