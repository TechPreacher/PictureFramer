import SwiftUI

/// Mask editing + AI removal UI. Shows the corrected image with the mask
/// as a red tint; drags paint (or erase) strokes through DisplayMapper —
/// the same canonical-coordinate discipline as the quad editor.
struct ReflectionEditView: View {
    @Bindable var model: EditorViewModel

    @State private var brushMode: ReflectionMask.Stroke.Mode = .add
    /// Brush radius in DISPLAY points; converted to canonical pixels per
    /// stroke so it feels constant on screen.
    @State private var brushRadiusPoints: CGFloat = 18
    @State private var currentStrokePoints: [CGPoint] = []   // canonical
    @State private var maskOverlay: CGImage?
    @State private var showPending = true
    /// Current pinch-zoom factor of the editing canvas. Gesture locations
    /// arrive in the content's own (unzoomed) coordinate space, so only
    /// the brush RADIUS needs this — zoomed in, strokes get finer.
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 12) {
            imageArea
            controls
        }
        .padding()
        .navigationTitle("Remove Reflections")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: regenerateOverlay)
        .onChange(of: model.reflectionMask?.strokes.count ?? 0) { _, _ in
            regenerateOverlay()
        }
    }

    // MARK: Image + mask overlay

    @ViewBuilder
    private var imageArea: some View {
        GeometryReader { proxy in
            if let pending = model.pendingCleaned, showPending {
                fittedImage(pending, in: proxy.size)
                    .overlay(alignment: .top) { compareBadge("After — hold to compare") }
            } else if !showPending, model.pendingCleaned != nil,
                      let original = model.correctedFullRes {
                fittedImage(original, in: proxy.size)
                    .overlay(alignment: .top) { compareBadge("Before") }
            } else if let corrected = model.correctedFullRes {
                let mapper = DisplayMapper(
                    imagePixelSize: CGSize(width: corrected.width, height: corrected.height),
                    viewSize: proxy.size
                )
                // Pinch to zoom, two-finger pan; one finger brushes.
                ZoomableContainer(zoomScale: $zoomScale) {
                    ZStack {
                        fittedImage(corrected, in: proxy.size)
                        if let maskOverlay {
                            Image(decorative: maskOverlay, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(brushGesture(mapper: mapper))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func fittedImage(_ image: CGImage, in size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
    }

    private func compareBadge(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    private func brushGesture(mapper: DisplayMapper) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                currentStrokePoints.append(mapper.pixelPoint(fromDisplay: value.location))
            }
            .onEnded { _ in
                guard !currentStrokePoints.isEmpty else { return }
                // Convert display-point radius → canonical pixels; divide
                // by the zoom so the brush stays finger-sized ON SCREEN,
                // i.e. finer in image pixels when zoomed in.
                let pixelsPerPoint = mapper.imagePixelSize.width / max(mapper.fittedRect.width, 1)
                model.addMaskStroke(.init(
                    mode: brushMode,
                    radius: brushRadiusPoints * pixelsPerPoint / max(zoomScale, 1),
                    points: currentStrokePoints
                ))
                currentStrokePoints = []
            }
    }

    /// Renders the mask as a red-tinted overlay image at preview scale.
    private func regenerateOverlay() {
        guard let mask = model.reflectionMask,
              let corrected = model.correctedFullRes else {
            maskOverlay = nil
            return
        }
        let scale = min(1, 1024 / CGFloat(max(corrected.width, corrected.height)))
        Task.detached(priority: .userInitiated) {
            let overlay = Self.tintedOverlay(mask: mask, scale: scale)
            await MainActor.run { maskOverlay = overlay }
        }
    }

    /// Red 45%-alpha where the mask is white, clear elsewhere.
    nonisolated private static func tintedOverlay(
        mask: ReflectionMask, scale: CGFloat
    ) -> CGImage? {
        guard let raster = mask.rasterize(scale: scale) else { return nil }
        let width = raster.width
        let height = raster.height
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let grayContext = CGContext(
            data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        grayContext.draw(raster, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where gray[i] > 127 {
            rgba[i * 4] = 255       // premultiplied red
            rgba[i * 4 + 3] = 115   // ~45% alpha
        }
        return rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if model.pendingCleaned != nil {
                pendingControls
            } else {
                maskEditingControls
            }
        }
    }

    @ViewBuilder
    private var pendingControls: some View {
        Button(showPending ? "Hold to see Before" : "Release for After") {}
            .buttonStyle(.bordered)
            .onLongPressGesture(minimumDuration: .infinity) {
            } onPressingChanged: { pressing in
                showPending = !pressing
            }
        HStack {
            Button("Try Again", role: .cancel) {
                model.discardPendingCleaned()
            }
            Spacer()
            Button("Use This") {
                model.acceptCleaned()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var maskEditingControls: some View {
        Picker("Brush", selection: $brushMode) {
            Text("Mark").tag(ReflectionMask.Stroke.Mode.add)
            Text("Erase").tag(ReflectionMask.Stroke.Mode.erase)
        }
        .pickerStyle(.segmented)

        HStack {
            Image(systemName: "circle.fill").font(.system(size: 8))
            Slider(value: $brushRadiusPoints, in: 6...48)
            Image(systemName: "circle.fill").font(.system(size: 20))
        }
        .accessibilityLabel("Brush size")

        HStack {
            Button("Cancel", role: .cancel) {
                model.exitReflectionRemoval()
            }
            Button("Re-detect") {
                model.redetectReflections()
                regenerateOverlay()
            }
            .buttonStyle(.bordered)
            Button("Clear") {
                model.clearReflectionMask()
                regenerateOverlay()
            }
            .buttonStyle(.bordered)
            .disabled(model.reflectionMask?.isEmpty ?? true)
            Spacer()
            Button {
                Task { await model.runReflectionRemoval() }
            } label: {
                if model.isRemovingReflections {
                    ProgressView()
                } else {
                    Label("Remove", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRemovingReflections
                      || (model.reflectionMask?.isEmpty ?? true))
        }
    }
}
