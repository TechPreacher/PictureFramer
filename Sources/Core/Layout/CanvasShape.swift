import CoreGraphics

/// Whether a canvas is wider than tall. Screens arrange themselves on this
/// and on size classes — never on interface orientation, which iPhone Duo's
/// inner display and iPad multitasking do not report reliably.
enum CanvasShape: Equatable, Sendable {
    case tall
    case wide

    init(size: CGSize) {
        self = size.width > size.height && size.height > 0 ? .wide : .tall
    }
}
