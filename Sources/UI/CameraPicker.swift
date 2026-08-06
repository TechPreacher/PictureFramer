import AVFoundation
import SwiftUI
import UIKit

/// Logic-free glue around the system camera UI. All real work happens in
/// `EditorViewModel.load(data:)` — this only converts the capture to JPEG
/// data and hands it to the callback. The capture is never written to the
/// photo library.
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the JPEG data of the confirmed capture ("Use Photo").
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False in the simulator and on devices without a camera; the UI
    /// hides the Take Photo button entirely.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// True when camera access is denied or restricted — the caller shows
    /// an error with a Settings link instead of presenting the camera.
    static var isAccessDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // 0.95 keeps the EXIF orientation tag and near-lossless pixels;
            // normalizedCGImage(from:) bakes the orientation in downstream.
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.95) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
