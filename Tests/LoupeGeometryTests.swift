import CoreGraphics
import Testing
@testable import PictureFramer

struct LoupeGeometryTests {

    private let geom = LoupeGeometry(
        focusDisplay: CGPoint(x: 200, y: 150), magnification: 2.5, diameter: 120)

    @Test func focusProjectsToCenter() {
        let c = geom.project(geom.focusDisplay)
        #expect(c == geom.center)
        #expect(geom.center == CGPoint(x: 60, y: 60))
    }

    @Test func offsetScalesByMagnification() {
        let p = geom.project(CGPoint(x: 210, y: 130))  // +10 x, -20 y
        #expect(p.x == 60 + 10 * 2.5)
        #expect(p.y == 60 + (-20) * 2.5)
    }

    @Test func placementGoesLeftWhenFocusOnRightHalf() {
        let rect = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 300, y: 100),
            areaSize: CGSize(width: 400, height: 600), diameter: 120, margin: 16)
        #expect(rect.minX == 16)
        #expect(rect.minY == 16)
        #expect(rect.width == 120)
        #expect(rect.height == 120)
    }

    @Test func placementGoesRightWhenFocusOnLeftHalf() {
        let rect = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 100, y: 100),
            areaSize: CGSize(width: 400, height: 600), diameter: 120, margin: 16)
        #expect(rect.minX == CGFloat(400 - 120 - 16))  // 264
        #expect(rect.minY == 16)
    }

    @Test func focusOnMidlineResolvesLeft() {
        let rect = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 200, y: 100),
            areaSize: CGSize(width: 400, height: 600), diameter: 120, margin: 16)
        #expect(rect.minX == 16)  // >= width/2 counts as right half → loupe left
    }

    @Test func placementStaysInsideAreaAtExtremes() {
        let size = CGSize(width: 400, height: 600)
        let left = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 0, y: 0), areaSize: size, diameter: 120, margin: 16)
        let right = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 400, y: 0), areaSize: size, diameter: 120, margin: 16)
        #expect(left.minX >= 0)
        #expect(left.maxX <= size.width)
        #expect(right.minX >= 0)
        #expect(right.maxX <= size.width)
    }
}
