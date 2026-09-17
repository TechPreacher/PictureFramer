import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var model = EditorViewModel()
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var cameraDenied = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .picking:
                    pickerScreen
                case .loading, .detecting:
                    ProgressView(model.stage == .loading ? "Loading photo…" : "Finding picture…")
                case .adjusting, .exporting:
                    EditorView(model: model)
                case .reflection:
                    ReflectionEditView(model: model)
                case .exported:
                    exportedScreen
                }
            }
            .navigationTitle("PictureFramer")
            .sensoryFeedback(.success, trigger: model.stage == .exported) { _, isExported in
                isExported
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { model.refreshProviderConfiguration() }) {
                SettingsView(settings: model.settings)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { data in
                    model.loadCapturedPhoto(data)
                }
            }
        }
    }

    /// Tall canvases stack hero, picker and buttons; wide ones (any device
    /// in landscape) put the hero beside them so nothing scrolls off.
    private var pickerScreen: some View {
        GeometryReader { proxy in
            Group {
                switch CanvasShape(size: proxy.size) {
                case .tall:
                    VStack(spacing: 24) {
                        heroImage
                            .frame(maxWidth: 520)
                        pickerControls
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .wide:
                    HStack(spacing: 24) {
                        heroImage
                            .frame(maxWidth: min(520, proxy.size.width * 0.5))
                        pickerControls
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        }
    }

    private var heroImage: some View {
        Image("OnboardingBeforeAfter")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("A crooked framed painting becomes perfectly straight")
    }

    private var pickerControls: some View {
        VStack(spacing: 24) {
            Picker("Crop mode", selection: $model.cropMode) {
                Text("With Frame & Wall").tag(CropMode.framed)
                Text("Painting Only").tag(CropMode.paintingOnly)
            }
            .pickerStyle(.segmented)
            Text(
                model.cropMode == .framed
                    ? "Pick a photo of a framed picture or painting. PictureFramer straightens it and keeps a strip of background around the frame."
                    : "Pick a photo of a framed picture or painting. PictureFramer straightens it and crops to just the painting — no frame, no wall."
            )
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            PhotosPicker(selection: $model.selection, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            if CameraSession.isAvailable {
                Button {
                    if CameraSession.isAccessDenied {
                        cameraDenied = true
                    } else {
                        cameraDenied = false
                        showCamera = true
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            }
            if cameraDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                HStack {
                    Text("Camera access is off.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Link("Open Settings", destination: settingsURL)
                        .font(.footnote)
                }
            }
        }
    }

    private var exportedScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("Saved to your photo library.")
                .font(.headline)
            Button("Straighten Another") {
                model.reset()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
