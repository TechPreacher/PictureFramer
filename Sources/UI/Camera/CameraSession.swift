import AVFoundation
import Foundation

/// Thin AVFoundation capture session for the in-app camera. Replaces
/// `UIImagePickerController`, whose camera UI is portrait-only: this
/// session follows the device orientation via `RotationCoordinator`, so
/// the preview rotates and captures come out correctly oriented (EXIF)
/// in landscape as well. The session opens the virtual multi-camera device
/// where available so that `videoZoomFactor` switches physical lenses; see
/// `CameraZoomRange`. Output is JPEG data for `EditorViewModel.load(data:)`;
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
    private var zoomRange: CameraZoomRange?

    /// Delivered once on the main queue after the session configures, so the
    /// view can show the zoom label and bound the pinch gesture. Set it before
    /// `start()`; it is consumed (and cleared) on the first `start()` so the
    /// closure cannot keep the view alive. Never called when no camera
    /// configures (simulator).
    var onZoomRangeReady: ((CameraZoomRange) -> Void)?

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

    /// The preview layer showing this session; drives rotation. Re-attaching
    /// a different layer (SwiftUI recreated the preview view) detaches the
    /// old one and rebuilds the rotation coordinator for the new one.
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        if let old = self.previewLayer, old !== previewLayer {
            old.session = nil
        }
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        self.previewLayer = previewLayer
        sessionQueue.async { [self] in
            rotationObservation = nil
            rotationCoordinator = nil
            makeRotationCoordinatorIfReady()
        }
    }

    /// The most capable back camera: a virtual multi-camera device where
    /// available, so `videoZoomFactor` switches physical lenses (ultra-wide
    /// → wide → telephoto); the bare wide-angle camera otherwise.
    private static var backCamera: AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    private func configure() {
        let callback = onZoomRangeReady
        onZoomRangeReady = nil
        guard let device = Self.backCamera,
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
        let range = CameraZoomRange(
            minimum: device.minAvailableVideoZoomFactor,
            maxAvailable: device.maxAvailableVideoZoomFactor,
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            hasUltraWide: device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera })
        zoomRange = range
        apply(zoomFactor: range.defaultFactor, to: device)
        DispatchQueue.main.async { callback?(range) }
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

    // MARK: Zoom

    /// Sets the device zoom (preview and capture alike). Clamped to the
    /// app's range and then to the device's own limits; no-op before the
    /// session has configured.
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device, let zoomRange else { return }
            apply(zoomFactor: zoomRange.clamped(factor), to: device)
        }
    }

    /// AVFoundation raises on a factor outside the device's available range,
    /// so clamp to the device's own bounds here regardless of the caller.
    private func apply(zoomFactor: CGFloat, to device: AVCaptureDevice) {
        let factor = min(max(zoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = factor
        device.unlockForConfiguration()
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
