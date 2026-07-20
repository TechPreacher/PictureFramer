import SwiftUI
import UIKit

struct EditorView: View {
    @Bindable var model: EditorViewModel
    /// Last drag translation, to turn the gesture's cumulative translation
    /// into per-tick deltas for panning.
    @State private var lastPanTranslation: CGSize = .zero
    /// The corner currently being dragged — drives the magnifier loupe.
    @State private var activeCorner: Quad.Corner?

    var body: some View {
        VStack(spacing: 12) {
            imageArea
            controls
        }
        .padding()
        .navigationTitle("Straighten")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.showCorrectedPreview) { activeCorner = nil }
    }

    @ViewBuilder
    private var imageArea: some View {
        GeometryReader { proxy in
            ZStack {
                if model.showCorrectedPreview {
                    correctedPreview
                } else if let sourceImage = model.sourceImage {
                    let mapper = DisplayMapper(
                        imagePixelSize: model.imagePixelSize,
                        viewSize: proxy.size
                    )
                    Image(decorative: sourceImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    if let quad = model.quad {
                        QuadOverlayView(
                            quad: quad,
                            marginQuad: model.cropMode == .framed ? model.marginQuad : nil,
                            mapper: mapper,
                            onCornerMoved: { corner, displayPoint in
                                model.moveCorner(corner, toDisplayPoint: displayPoint, mapper: mapper)
                            },
                            onDragBegan: { activeCorner = $0 },
                            onDragEnded: { activeCorner = nil }
                        )
                        if let activeCorner {
                            MagnifierLoupeView(
                                image: sourceImage,
                                mapper: mapper,
                                quad: quad,
                                corner: activeCorner,
                                areaSize: proxy.size
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var correctedPreview: some View {
        GeometryReader { proxy in
            ZStack {
                if let preview = model.previewImage {
                    let aspect = CGFloat(preview.width) / CGFloat(preview.height)
                    let fittedWidth = min(proxy.size.width, proxy.size.height * aspect)
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let delta = CGSize(
                                        width: value.translation.width - lastPanTranslation.width,
                                        height: value.translation.height - lastPanTranslation.height
                                    )
                                    lastPanTranslation = value.translation
                                    model.pan(byDisplayDelta: delta, previewFittedWidth: fittedWidth)
                                }
                                .onEnded { _ in
                                    lastPanTranslation = .zero
                                }
                        )
                        .accessibilityLabel("Corrected preview. Drag to recenter the picture.")
                }
                if model.isRenderingPreview {
                    ProgressView()
                }
                VStack {
                    Spacer()
                    if model.isPanned {
                        Button("Recenter") {
                            model.resetPan()
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 8)
                    } else {
                        Text("Drag to pan image")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            if model.detectionFailed {
                Label(
                    "Couldn't find the picture automatically — drag the corners onto its frame.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            if let errorMessage = model.errorMessage {
                HStack {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    if model.exportDenied,
                       let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: settingsURL)
                            .font(.footnote)
                    }
                }
            }

            Picker("Crop mode", selection: $model.cropMode) {
                Text("With Frame & Wall").tag(CropMode.framed)
                Text("Painting Only").tag(CropMode.paintingOnly)
            }
            .pickerStyle(.segmented)
            .disabled(model.stage == .exporting)

            Picker("View", selection: $model.showCorrectedPreview) {
                Text("Adjust").tag(false)
                Text("Preview").tag(true)
            }
            .pickerStyle(.segmented)

            if model.cropMode == .framed {
                MarginControlView(marginPixels: $model.marginPixels)
            }

            HStack {
                Button {
                    Task { await model.beginReflectionRemoval() }
                } label: {
                    Label(
                        model.cleanedImage != nil
                            ? "Reflections Removed" : "Remove Reflections",
                        systemImage: model.cleanedImage != nil ? "checkmark.seal" : "sparkles"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(model.quad == nil || !model.isProviderConfigured)
                if !model.isProviderConfigured {
                    Text("Set up an AI provider in Settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Start Over", role: .cancel) {
                    model.reset()
                }
                Spacer()
                Button {
                    Task { await model.export() }
                } label: {
                    if model.stage == .exporting {
                        ProgressView()
                    } else {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.stage == .exporting || model.quad == nil)
            }
        }
    }
}
