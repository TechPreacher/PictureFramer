import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct EditorLayoutTests {

    @Test func compactWidthAlwaysStacks() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 390, height: 844), isRegularWidth: false) == .stacked)
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 844, height: 390), isRegularWidth: false) == .stacked)
    }

    /// iPhone Duo inner display, portrait pose: regular width but taller
    /// than wide — keep the stack so the picture gets the height.
    @Test func regularWidthPortraitStacks() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 669, height: 951), isRegularWidth: true) == .stacked)
    }

    /// iPhone Duo inner display, landscape pose.
    @Test func regularWidthLandscapeGoesSideBySide() {
        let layout = EditorLayout.resolve(canvasSize: CGSize(width: 951, height: 669), isRegularWidth: true)
        #expect(layout == .sideBySide(controlsWidth: 380))
    }

    @Test func controlsWidthIsCappedByFractionOnNarrowCanvases() {
        let layout = EditorLayout.resolve(canvasSize: CGSize(width: 700, height: 500), isRegularWidth: true)
        #expect(layout == .sideBySide(controlsWidth: 700 * 0.42))
    }

    @Test func controlsWidthIsCappedByMaximumOnWideCanvases() {
        let layout = EditorLayout.resolve(canvasSize: CGSize(width: 1400, height: 900), isRegularWidth: true)
        #expect(layout == .sideBySide(controlsWidth: 380))
    }

    @Test func squareCanvasStacks() {
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 800, height: 800), isRegularWidth: true) == .stacked)
    }

    @Test func degenerateSizesStack() {
        #expect(EditorLayout.resolve(canvasSize: .zero, isRegularWidth: true) == .stacked)
        #expect(EditorLayout.resolve(canvasSize: CGSize(width: 1, height: 0), isRegularWidth: true) == .stacked)
    }
}
