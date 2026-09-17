import AVFoundation
import Foundation

/// Thin AVFoundation capture session for the in-app camera. Replaces
/// `UIImagePickerController`, whose camera UI is portrait-only: this
/// session follows the device orientation via `RotationCoordinator`, so
/// the preview rotates and captures come out correctly oriented (EXIF)
/// in landscape as well. Output is JPEG data for `EditorViewModel.load(data:)`;
/// nothing is written to the photo library.
final class CameraSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.corti.PictureFramer.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var pendingCapture: ((Data?) -> Void)?
    private var isConfigured = false

    /// False in the simulator and on devices without a back camera; the
    /// UI hides the Take Photo button entirely.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// True when camera access is denied or restricted — the caller shows
    /// an error with a Settings link instead of presenting the camera.
    static var isAccessDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    // MARK: Lifecycle

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// The preview layer showing this session; drives rotation.
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        self.previewLayer = previewLayer
        sessionQueue.async { [self] in makeRotationCoordinatorIfReady() }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        session.commitConfiguration()
        self.device = device
        isConfigured = true
        makeRotationCoordinatorIfReady()
    }

    /// Needs both the device (after configure) and the preview layer
    /// (after attach); whichever arrives second creates the coordinator.
    private func makeRotationCoordinatorIfReady() {
        guard rotationCoordinator == nil, let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                guard let connection = self?.previewLayer?.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
    }

    // MARK: Capture

    /// Takes one JPEG. The completion runs on the main queue with `nil` on
    /// failure.
    func capture(completion: @escaping (Data?) -> Void) {
        sessionQueue.async { [self] in
            guard isConfigured, pendingCapture == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            pendingCapture = completion
            if let connection = photoOutput.connection(with: .video), let rotationCoordinator {
                let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        sessionQueue.async { [self] in
            let completion = pendingCapture
            pendingCapture = nil
            DispatchQueue.main.async { completion?(data) }
        }
    }
}
