import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct CameraZoomRangeTests {
    /// iPhone Pro triple camera: ultra-wide at 1, wide at 2, telephoto at 6.
    static let triple = CameraZoomRange(
        minimum: 1, maxAvailable: 123, switchOverFactors: [2, 6], hasUltraWide: true)
    /// Ultra-wide + wide only.
    static let dualWide = CameraZoomRange(
        minimum: 1, maxAvailable: 60, switchOverFactors: [2], hasUltraWide: true)
    /// Wide + telephoto, no ultra-wide: factor 1 is already the wide lens.
    static let dual = CameraZoomRange(
        minimum: 1, maxAvailable: 60, switchOverFactors: [2], hasUltraWide: false)
    /// Single wide lens.
    static let single = CameraZoomRange(
        minimum: 1, maxAvailable: 16, switchOverFactors: [], hasUltraWide: false)

    @Test func tripleCameraDefaultsToWideLensAndCapsAtTelephoto() {
        let range = Self.triple
        #expect(range.minimum == 1)
        #expect(range.maximum == 6)
        #expect(range.defaultFactor == 2)
        #expect(range.isZoomable)
    }

    @Test func tripleCameraDisplayFactors() {
        let range = Self.triple
        #expect(range.displayMultiplier == 0.5)
        #expect(range.displayFactor(for: 1) == 0.5)
        #expect(range.displayFactor(for: 2) == 1)
        #expect(range.displayFactor(for: 6) == 3)
    }

    @Test func dualWideCapsAtWideLens() {
        let range = Self.dualWide
        #expect(range.maximum == 2)
        #expect(range.defaultFactor == 2)
        #expect(range.isZoomable)
        #expect(range.displayLabel(for: 2) == "1×")
    }

    @Test func dualWithoutUltraWideKeepsFactorOneAsWide() {
        let range = Self.dual
        #expect(range.displayMultiplier == 1)
        #expect(range.defaultFactor == 1)
        #expect(range.maximum == 2)
        #expect(range.displayLabel(for: 1) == "1×")
        #expect(range.displayLabel(for: 2) == "2×")
    }

    @Test func singleLensIsNotZoomable() {
        let range = Self.single
        #expect(!range.isZoomable)
        #expect(range.maximum == range.minimum)
        #expect(range.defaultFactor == 1)
        #expect(range.pinched(from: 1, by: 3) == 1)
        #expect(range.pinched(from: 1, by: 0.2) == 1)
    }

    @Test func maxAvailableBelowLongestLensWins() {
        let range = CameraZoomRange(
            minimum: 1, maxAvailable: 4, switchOverFactors: [2, 6], hasUltraWide: true)
        #expect(range.maximum == 4)
        #expect(range.pinched(from: 2, by: 10) == 4)
    }

    @Test func pinchScalesAndClampsBothEnds() {
        let range = Self.triple
        #expect(range.pinched(from: 2, by: 1.5) == 3)
        #expect(range.pinched(from: 2, by: 10) == 6)
        #expect(range.pinched(from: 2, by: 0.1) == 1)
    }

    @Test func degenerateMagnificationKeepsStart() {
        let range = Self.triple
        #expect(range.pinched(from: 3, by: 0) == 3)
        #expect(range.pinched(from: 3, by: -1) == 3)
        #expect(range.pinched(from: 3, by: .nan) == 3)
        #expect(range.pinched(from: 3, by: .infinity) == 3)
    }

    @Test func clampedHandlesOutOfRangeAndNonFinite() {
        let range = Self.triple
        #expect(range.clamped(0) == 1)
        #expect(range.clamped(100) == 6)
        #expect(range.clamped(.nan) == 1)
        #expect(range.clamped(.infinity) == 1)
    }

    @Test func labelsRoundToOneDecimalAndDropTrailingZero() {
        let range = Self.triple
        #expect(range.displayLabel(for: 1) == "0.5×")
        #expect(range.displayLabel(for: 2) == "1×")
        #expect(range.displayLabel(for: 5) == "2.5×")
        #expect(range.displayLabel(for: 2.4) == "1.2×")
        #expect(range.displayLabel(for: 5.92) == "3×")   // 2.96 rounds to 3.0
    }

    @Test func nonFiniteInputsFallBackToMinimum() {
        let range = Self.triple
        #expect(range.displayLabel(for: .infinity) == "0.5×")
        #expect(range.displayLabel(for: .nan) == "0.5×")
        #expect(range.displayLabel(for: .infinity) == range.displayLabel(for: range.minimum))
        #expect(range.pinched(from: .nan, by: 1.5) == range.minimum)
    }

    @Test func degenerateInputsFallBackToUnitRange() {
        let zero = CameraZoomRange(
            minimum: 0, maxAvailable: 0, switchOverFactors: [], hasUltraWide: false)
        #expect(zero.minimum == 1)
        #expect(zero.maximum == 1)
        #expect(!zero.isZoomable)
        #expect(zero.displayLabel(for: zero.defaultFactor) == "1×")

        let nan = CameraZoomRange(
            minimum: .nan, maxAvailable: .nan, switchOverFactors: [0], hasUltraWide: true)
        #expect(nan.minimum == 1)
        #expect(nan.maximum == 1)
        #expect(nan.displayMultiplier == 1)
    }
}
