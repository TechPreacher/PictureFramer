import CoreGraphics
import Foundation

/// Pure zoom math for the in-app camera. All factors are AVFoundation
/// `videoZoomFactor` values of the (virtual) capture device; this type never
/// touches AVFoundation so it stays unit-testable in Core.
///
/// On a virtual device that includes the ultra-wide lens, factor 1.0 is the
/// ultra-wide lens and the wide lens sits at the first switch-over factor —
/// the one the Camera app labels "1×". `displayMultiplier` converts between
/// the device's factor and that user-facing factor.
struct CameraZoomRange: Equatable, Sendable {
    /// Smallest allowed `videoZoomFactor` (the widest lens).
    let minimum: CGFloat
    /// Largest allowed `videoZoomFactor`: the longest lens's native factor,
    /// or the device limit if that is lower. No digital zoom past it.
    let maximum: CGFloat
    /// Multiply a device factor by this to get the user-facing factor.
    let displayMultiplier: CGFloat

    /// - Parameters:
    ///   - minimum: `minAvailableVideoZoomFactor`.
    ///   - maxAvailable: `maxAvailableVideoZoomFactor`.
    ///   - switchOverFactors: `virtualDeviceSwitchOverVideoZoomFactors`,
    ///     ascending; empty on a single-lens device.
    ///   - hasUltraWide: whether the constituent devices include the
    ///     ultra-wide lens (then factor 1.0 is ultra-wide, not wide).
    init(minimum: CGFloat, maxAvailable: CGFloat, switchOverFactors: [CGFloat], hasUltraWide: Bool) {
        let lower = minimum.isFinite && minimum > 0 ? minimum : 1
        let longestLens = switchOverFactors.last ?? 1
        let upper = maxAvailable.isFinite ? min(maxAvailable, longestLens) : longestLens
        self.minimum = lower
        self.maximum = max(lower, upper)
        let wide = hasUltraWide ? (switchOverFactors.first ?? 1) : 1
        self.displayMultiplier = wide.isFinite && wide > 0 ? 1 / wide : 1
    }

    /// False on a single-lens device: pinching does nothing and the UI
    /// hides the factor label.
    var isZoomable: Bool { maximum > minimum }

    /// The wide lens — what the Camera app shows as "1×".
    var defaultFactor: CGFloat { clamped(1 / displayMultiplier) }

    func clamped(_ factor: CGFloat) -> CGFloat {
        guard factor.isFinite else { return minimum }
        return min(max(factor, minimum), maximum)
    }

    /// Zoom after a pinch that began at `start`; degenerate magnifications
    /// (zero, negative, non-finite) leave the zoom where it started.
    func pinched(from start: CGFloat, by magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite, magnification > 0 else { return clamped(start) }
        return clamped(start * magnification)
    }

    func displayFactor(for factor: CGFloat) -> CGFloat {
        factor * displayMultiplier
    }

    /// "0.5×", "1×", "2.5×" — one decimal, trailing ".0" dropped.
    func displayLabel(for factor: CGFloat) -> String {
        let rounded = (displayFactor(for: factor) * 10).rounded() / 10
        // Non-finite input would trap in Int(_:); `minimum` is always finite.
        guard rounded.isFinite else { return displayLabel(for: minimum) }
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", Double(rounded))
        return text + "×"
    }
}
