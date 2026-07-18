import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var model = EditorViewModel()
    @State private var showSettings = false

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
                    Text("Reflection editor")
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
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: model.settings)
            }
        }
    }

    private var pickerScreen: some View {
        VStack(spacing: 24) {
            Image("OnboardingBeforeAfter")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .accessibilityLabel("A crooked framed painting becomes perfectly straight")
            Text("Pick a photo of a framed picture or painting. PictureFramer straightens it and keeps a strip of background around the frame.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            PhotosPicker(selection: $model.selection, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
