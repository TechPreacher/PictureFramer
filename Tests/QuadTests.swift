import CoreGraphics
import Testing
@testable import PictureFramer

struct QuadTests {

    private func axisAlignedQuad(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Quad {
        Quad(
            topLeft: CGPoint(x: x, y: y + height),
            topRight: CGPoint(x: x + width, y: y + height),
            bottomLeft: CGPoint(x: x, y: y),
            bottomRight: CGPoint(x: x + width, y: y)
        )
    }

    @Test func centroidOfRectangleIsItsCenter() {
        let quad = axisAlignedQuad(x: 10, y: 20, width: 100, height: 60)
        #expect(quad.centroid == CGPoint(x: 60, y: 50))
    }

    @Test func rectangleIsConvex() {
        #expect(axisAlignedQuad(x: 0, y: 0, width: 10, height: 10).isConvex)
    }

    @Test func reflexCornerIsNotConvex() {
        var quad = axisAlignedQuad(x: 0, y: 0, width: 100, height: 100)
        quad.bottomRight = CGPoint(x: 30, y: 50)  // pushed inside → reflex
        #expect(!quad.isConvex)
    }

    @Test func selfIntersectingQuadIsNotConvex() {
        // Swap the two top corners so the perimeter crosses itself.
        let quad = Quad(
            topLeft: CGPoint(x: 100, y: 100),
            topRight: CGPoint(x: 0, y: 100),
            bottomLeft: CGPoint(x: 0, y: 0),
            bottomRight: CGPoint(x: 100, y: 0)
        )
        #expect(!quad.isConvex)
    }

    @Test func degenerateQuadIsNotConvex() {
        let p = CGPoint(x: 5, y: 5)
        let quad = Quad(topLeft: p, topRight: p, bottomLeft: p, bottomRight: p)
        #expect(!quad.isConvex)
    }

    @Test func clampPullsOutsideCornersIntoBounds() {
        let quad = Quad(
            topLeft: CGPoint(x: -50, y: 250),
            topRight: CGPoint(x: 300, y: 220),
            bottomLeft: CGPoint(x: -20, y: -10),
            bottomRight: CGPoint(x: 280, y: -5)
        )
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let clamped = quad.clamped(to: bounds)
        for corner in clamped.perimeterCorners {
            #expect(bounds.contains(corner) || corner.x == bounds.maxX || corner.y == bounds.maxY)
            #expect(corner.x >= bounds.minX && corner.x <= bounds.maxX)
            #expect(corner.y >= bounds.minY && corner.y <= bounds.maxY)
        }
    }

    @Test func clampLeavesInsideQuadUntouched() {
        let quad = axisAlignedQuad(x: 10, y: 10, width: 50, height: 50)
        #expect(quad.clamped(to: CGRect(x: 0, y: 0, width: 100, height: 100)) == quad)
    }

    @Test func scaleMultipliesAllCorners() {
        let quad = axisAlignedQuad(x: 10, y: 20, width: 100, height: 50)
        let scaled = quad.scaled(by: 2)
        #expect(scaled.topLeft == CGPoint(x: 20, y: 140))
        #expect(scaled.bottomRight == CGPoint(x: 220, y: 40))
    }

    @Test func cornerSubscriptRoundTrips() {
        var quad = axisAlignedQuad(x: 0, y: 0, width: 10, height: 10)
        let moved = CGPoint(x: -3, y: 12)
        quad[.topRight] = moved
        #expect(quad[.topRight] == moved)
        #expect(quad.topRight == moved)
    }
}
