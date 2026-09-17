import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct EditorLayoutTests {

    @Test func phonePortraitStacks() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 390, height: 844)) == .stacked)
    }

    /// Phone landscape: the stack would leave <100 pt for the image, and the
    /// short height gets the wider (half-width, still capped) column.
    @Test func phoneLandscapeGoesSideBySideWithWiderColumn() {
        let layout = EditorLayout.resolve(canvasSize: CGSize(width: 844, height: 390))
        #expect(layout == .sideBySide(controlsWidth: min(380, 844 * 0.5)))
    }

    @Test func shortCanvasThresholdIsExclusive() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 800, height: 500)) == .sideBySide(controlsWidth: 800 * 0.42))
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 800, height: 499)) == .sideBySide(controlsWidth: 380))
    }

    /// iPhone Duo inner display, portrait pose.
    @Test func duoPortraitStacks() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 669, height: 951)) == .stacked)
    }

    /// iPhone Duo inner display, landscape pose.
    @Test func duoLandscapeGoesSideBySide() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 951, height: 669)) == .sideBySide(controlsWidth: 380))
    }

    @Test func controlsWidthIsCappedByMaximumOnWideCanvases() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 1400, height: 900)) == .sideBySide(controlsWidth: 380))
    }

    @Test func squareCanvasStacks() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 800, height: 800)) == .stacked)
    }

    @Test func degenerateSizesStack() {
        #expect(EditorLayout.resolve(canvasSize: .zero) == .stacked)
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 1, height: 0)) == .stacked)
    }
}
