import AVFoundation
import SwiftUI
import UIKit

/// Full-screen in-app camera. The preview follows the device orientation;
/// the shutter sits below the preview on tall canvases and beside it on
/// wide ones, so landscape paintings can be shot in landscape.
struct CameraCaptureView: View {
    /// Called with the JPEG data of the capture.
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraSession()
    @State private var isCapturing = false

    private let barSize: CGFloat = 112

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                switch CanvasShape(size: proxy.size) {
                case .tall:
                    VStack(spacing: 0) {
                        preview
                        controls(axis: .horizontal)
                            .frame(height: barSize)
                    }
                case .wide:
                    HStack(spacing: 0) {
                        preview
                        controls(axis: .vertical)
                            .frame(width: barSize)
                    }
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

    private enum Axis { case horizontal, vertical }

    @ViewBuilder
    private func controls(axis: Axis) -> some View {
        let layout: AnyLayout = axis == .horizontal ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
        layout {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
                .frame(maxWidth: axis == .horizontal ? .infinity : nil,
                       maxHeight: axis == .vertical ? .infinity : nil)
            shutter
            Color.clear
                .frame(maxWidth: axis == .horizontal ? .infinity : nil,
                       maxHeight: axis == .vertical ? .infinity : nil)
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

/// UIView whose backing layer is the session's preview layer.
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
