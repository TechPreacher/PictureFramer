import Foundation

/// Why an in-app camera capture produced no photo. Each case's description
/// carries enough detail to diagnose a hardware-only failure from the
/// on-screen alert alone (the `.capture` case keeps the AVFoundation error's
/// domain, code and message).
enum CameraCaptureError: LocalizedError, Equatable {
    /// The session never configured (no camera, or setup failed).
    case notConfigured
    /// A previous capture has not delivered yet.
    case captureInProgress
    /// AVFoundation reported an error while processing the photo.
    case capture(underlying: NSError)
    /// Processing finished without error but the photo had no file data.
    case noImageData

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Camera session is not configured."
        case .captureInProgress:
            "Another capture is still in progress."
        case let .capture(underlying):
            "Capture error \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
        case .noImageData:
            "The captured photo contained no image data."
        }
    }
}
