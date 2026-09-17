import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct CanvasShapeTests {
    @Test func widerThanTallIsWide() {
        #expect(CanvasShape(size: CGSize(width: 2, height: 1)) == .wide)
    }
    @Test func tallerThanWideIsTall() {
        #expect(CanvasShape(size: CGSize(width: 1, height: 2)) == .tall)
    }
    @Test func squareIsTall() {
        #expect(CanvasShape(size: CGSize(width: 5, height: 5)) == .tall)
    }
    @Test func zeroHeightIsTall() {
        #expect(CanvasShape(size: CGSize(width: 5, height: 0)) == .tall)
        #expect(CanvasShape(size: .zero) == .tall)
    }
}
