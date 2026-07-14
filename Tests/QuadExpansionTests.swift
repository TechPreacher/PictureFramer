import CoreGraphics
import Testing
@testable import PictureFramer

struct QuadExpansionTests {

    private static let accuracy: CGFloat = 1e-6

    private func expectClose(
        _ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = accuracy,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let distance = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        #expect(distance <= tolerance, "expected \(a) ≈ \(b)", sourceLocation: sourceLocation)
    }

    /// Distance from point to the infinite line through a and b.
    private func distance(from p: CGPoint, toLineThrough a: CGPoint, _ b: CGPoint) -> CGFloat {
        let edge = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let length = (edge.dx * edge.dx + edge.dy * edge.dy).squareRoot()
        return abs((p.x - a.x) * edge.dy - (p.y - a.y) * edge.dx) / length
    }

    private func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Quad {
        Quad(
            topLeft: CGPoint(x: x, y: y + height),
            topRight: CGPoint(x: x + width, y: y + height),
            bottomLeft: CGPoint(x: x, y: y),
            bottomRight: CGPoint(x: x + width, y: y)
        )
    }

    @Test func zeroMarginReturnsIdenticalQuad() {
        let quad = rect(x: 10, y: 10, width: 100, height: 60)
        #expect(quad.expanded(by: 0) == quad)
    }

    @Test func axisAlignedRectangleExpandsToOutsetRectangle() throws {
        let quad = rect(x: 100, y: 100, width: 200, height: 150)
        let expanded = try #require(quad.expanded(by: 25))
        expectClose(expanded.bottomLeft, CGPoint(x: 75, y: 75))
        expectClose(expanded.topRight, CGPoint(x: 325, y: 275))
        expectClose(expanded.topLeft, CGPoint(x: 75, y: 275))
        expectClose(expanded.bottomRight, CGPoint(x: 325, y: 75))
    }

    @Test func rotatedSquareCornersMoveAlongDiagonals() throws {
        // Square rotated 45°: corners on the axes around center (0, 0).
        let quad = Quad(
            topLeft: CGPoint(x: -100, y: 0),
            topRight: CGPoint(x: 0, y: 100),
            bottomLeft: CGPoint(x: 0, y: -100),
            bottomRight: CGPoint(x: 100, y: 0)
        )
        let margin: CGFloat = 30
        let expanded = try #require(quad.expanded(by: margin))
        // Each corner slides outward along its diagonal by margin·√2.
        let d = margin * 2.0.squareRoot()
        expectClose(expanded.topLeft, CGPoint(x: -100 - d, y: 0))
        expectClose(expanded.topRight, CGPoint(x: 0, y: 100 + d))
        expectClose(expanded.bottomLeft, CGPoint(x: 0, y: -100 - d))
        expectClose(expanded.bottomRight, CGPoint(x: 100 + d, y: 0))
    }

    @Test func keystonedTrapezoidEdgesAreExactlyMarginAway() throws {
        // Narrower at the top, like a painting photographed from below.
        let quad = Quad(
            topLeft: CGPoint(x: 120, y: 400),
            topRight: CGPoint(x: 380, y: 390),
            bottomLeft: CGPoint(x: 80, y: 100),
            bottomRight: CGPoint(x: 430, y: 110)
        )
        let margin: CGFloat = 40
        let expanded = try #require(quad.expanded(by: margin))
        let original = quad.perimeterCorners
        let grown = expanded.perimeterCorners
        for i in 0..<4 {
            let a = original[i]
            let b = original[(i + 1) % 4]
            // Both endpoints of the expanded edge sit exactly `margin` from
            // the original edge's line.
            #expect(abs(distance(from: grown[i], toLineThrough: a, b) - margin) < 1e-6)
            #expect(abs(distance(from: grown[(i + 1) % 4], toLineThrough: a, b) - margin) < 1e-6)
        }
        #expect(expanded.isConvex)
    }

    @Test func oversizedMarginClampedStaysInsideBounds() throws {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        let quad = rect(x: 50, y: 40, width: 400, height: 320)
        // Margin far larger than the 40–50 px of surrounding background.
        let expanded = try #require(quad.expanded(by: 300))
        let clamped = expanded.clamped(to: bounds)
        for corner in clamped.perimeterCorners {
            #expect(corner.x >= bounds.minX && corner.x <= bounds.maxX)
            #expect(corner.y >= bounds.minY && corner.y <= bounds.maxY)
        }
        // Degrades to "use everything": clamped quad covers the full image.
        expectClose(clamped.bottomLeft, CGPoint(x: 0, y: 0))
        expectClose(clamped.topRight, CGPoint(x: 500, y: 400))
    }

    @Test func degenerateQuadReturnsNil() {
        // All corners collinear → adjacent edges parallel.
        let quad = Quad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 100, y: 0),
            bottomLeft: CGPoint(x: 200, y: 0),
            bottomRight: CGPoint(x: 300, y: 0)
        )
        #expect(quad.expanded(by: 10) == nil)
    }

    @Test func zeroLengthEdgeReturnsNil() {
        let p = CGPoint(x: 50, y: 50)
        let quad = Quad(
            topLeft: p,
            topRight: p,
            bottomLeft: CGPoint(x: 0, y: 0),
            bottomRight: CGPoint(x: 100, y: 0)
        )
        #expect(quad.expanded(by: 10) == nil)
    }

    @Test func extremeAspectRatioExpandsCorrectly() throws {
        let quad = rect(x: 0, y: 0, width: 4000, height: 80)
        let expanded = try #require(quad.expanded(by: 15))
        expectClose(expanded.bottomLeft, CGPoint(x: -15, y: -15))
        expectClose(expanded.topRight, CGPoint(x: 4015, y: 95))
        #expect(expanded.isConvex)
    }

    @Test func negativeMarginShrinks() throws {
        let quad = rect(x: 100, y: 100, width: 200, height: 150)
        let shrunk = try #require(quad.expanded(by: -20))
        expectClose(shrunk.bottomLeft, CGPoint(x: 120, y: 120))
        expectClose(shrunk.topRight, CGPoint(x: 280, y: 230))
    }

    @Test func negativeMarginLargerThanHalfSizeReturnsNil() {
        // Shrinking a 150-tall rect by 80 per side crosses the edges.
        let quad = rect(x: 100, y: 100, width: 200, height: 150)
        #expect(quad.expanded(by: -80) == nil)
    }

    @Test(arguments: [CGFloat(1), 7.5, 42, 250])
    func expansionIsInverseOfShrinking(margin: CGFloat) throws {
        let quad = Quad(
            topLeft: CGPoint(x: 90, y: 610),
            topRight: CGPoint(x: 700, y: 580),
            bottomLeft: CGPoint(x: 110, y: 90),
            bottomRight: CGPoint(x: 680, y: 120)
        )
        let roundTripped = try #require(quad.expanded(by: margin)?.expanded(by: -margin))
        for (a, b) in zip(roundTripped.perimeterCorners, quad.perimeterCorners) {
            expectClose(a, b, tolerance: 1e-6)
        }
    }
}
