import AVFoundation
import SwiftUI
import UIKit

/// Full-screen in-app camera. The preview follows the device orientation;
/// the shutter sits below the preview on tall canvases and beside it on
/// wide ones, so landscape paintings can be shot in landscape.
///
/// The arrangement switches through `AnyLayout`, never through separate
/// `VStack`/`HStack` branches: a branch change would give `CameraPreview`
/// a new identity, tear down the `UIView` whose layer is the session's
/// preview layer, and create another — on device that blanks the preview
/// and can crash when the old layer deallocates under a running session.
struct CameraCaptureView: View {
    /// Called with the JPEG data of the capture.
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraSession()
    @State private var isCapturing = false

    private let barSize: CGFloat = 112

    var body: some View {
        GeometryReader { proxy in
            let isWide = CanvasShape(size: proxy.size) == .wide
            let outer: AnyLayout = isWide
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            ZStack {
                Color.black.ignoresSafeArea()
                outer {
                    preview
                    controls(isWide: isWide)
                        .frame(width: isWide ? barSize : nil, height: isWide ? nil : barSize)
                }
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var preview: some View {
        CameraPreview(session: camera)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Camera preview")
    }

    @ViewBuilder
    private func controls(isWide: Bool) -> some View {
        let bar: AnyLayout = isWide ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
        bar {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
                .frame(maxWidth: isWide ? nil : .infinity, maxHeight: isWide ? .infinity : nil)
            shutter
            Color.clear
                .frame(maxWidth: isWide ? nil : .infinity, maxHeight: isWide ? .infinity : nil)
        }
        .padding(12)
    }

    private var shutter: some View {
        Button {
            guard !isCapturing else { return }
            isCapturing = true
            camera.capture { data in
                isCapturing = false
                if let data {
                    onCapture(data)
                    dismiss()
                }
            }
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(.white).frame(width: 62, height: 62)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .accessibilityLabel("Take Photo")
    }
}

/// UIView whose backing layer is the session's preview layer. Must keep a
/// stable identity for the life of the capture view (see above).
private struct CameraPreview: UIViewRepresentable {
    let session: CameraSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        session.attach(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
