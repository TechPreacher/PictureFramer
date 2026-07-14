import CoreImage
import PhotosUI
import SwiftUI

@Observable @MainActor
final class EditorViewModel {

    enum Stage: Equatable {
        case picking
        case loading
        case detecting
        case adjusting
        case exporting
        case exported
    }

    var stage: Stage = .picking

    var selection: PhotosPickerItem? {
        didSet {
            guard let selection else { return }
            loadTask?.cancel()
            loadTask = Task { await load(item: selection) }
        }
    }

    private(set) var sourceImage: CGImage?
    /// Single source of truth for the crop, in canonical full-res pixels.
    var quad: Quad?
    var marginPixels: Double = 40 {
        didSet { regeneratePreview() }
    }
    /// Crop-window shift in canonical source pixels — lets the user
    /// recenter when a shadow skewed the detected bounds off the painting.
    private(set) var panOffset: CGVector = .zero
    var isPanned: Bool { panOffset != .zero }
    private(set) var previewImage: CGImage?
    private(set) var isRenderingPreview = false
    private(set) var detectionFailed = false
    /// Export was refused for lack of photo-library permission — the UI
    /// offers a Settings deep link.
    private(set) var exportDenied = false
    var showCorrectedPreview = false {
        didSet { regeneratePreview() }
    }
    var errorMessage: String?

    private let pipeline: FramingPipeline
    private let exporter: PhotoLibraryExporter
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// Downscaled copy of the source, computed once per photo — interactive
    /// preview renders reuse it instead of re-downscaling the full-res
    /// image on every slider tick.
    private var previewBase: CGImage?
    private var previewScale: CGFloat = 1

    init(pipeline: FramingPipeline = FramingPipeline(), exporter: PhotoLibraryExporter = PhotoLibraryExporter()) {
        self.pipeline = pipeline
        self.exporter = exporter
    }

    var imagePixelSize: CGSize {
        guard let sourceImage else { return .zero }
        return CGSize(width: sourceImage.width, height: sourceImage.height)
    }

    /// The quad that will actually be cropped (margin included), for the
    /// dashed on-screen outline.
    var marginQuad: Quad? {
        guard let quad, let sourceImage else { return nil }
        return pipeline.effectiveQuad(
            from: quad,
            marginPixels: CGFloat(marginPixels),
            imageSize: CGSize(width: sourceImage.width, height: sourceImage.height),
            panOffset: panOffset
        )
    }

    // MARK: Loading

    private func load(item: PhotosPickerItem) async {
        stage = .loading
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = Self.normalizedCGImage(from: data) else {
                errorMessage = "Couldn't load that photo."
                stage = .picking
                return
            }
            sourceImage = image
            let base = await Task.detached(priority: .userInitiated) {
                downscaled(image, maxDimension: 1600)
            }.value
            previewBase = base
            previewScale = CGFloat(base.width) / CGFloat(image.width)
            await runDetection()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Couldn't load that photo."
            stage = .picking
        }
    }

    /// Decodes image data with EXIF orientation baked in, so canonical
    /// space never has to consider orientation.
    nonisolated static func normalizedCGImage(from data: Data) -> CGImage? {
        guard let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return nil
        }
        return RenderContext.shared.makeCGImage(from: ciImage)
    }

    // MARK: Detection

    func runDetection() async {
        guard let sourceImage else { return }
        stage = .detecting
        detectionFailed = false
        panOffset = .zero
        do {
            if let detected = try await pipeline.detectQuad(in: sourceImage) {
                quad = detected
            } else {
                quad = Self.fallbackQuad(for: imagePixelSize)
                detectionFailed = true
            }
        } catch {
            quad = Self.fallbackQuad(for: imagePixelSize)
            detectionFailed = true
        }
        stage = .adjusting
        regeneratePreview()
    }

    /// Centered quad covering 80% of the image — starting point for manual
    /// adjustment when detection finds nothing.
    nonisolated static func fallbackQuad(for size: CGSize) -> Quad {
        let insetX = size.width * 0.1
        let insetY = size.height * 0.1
        return Quad(
            topLeft: CGPoint(x: insetX, y: size.height - insetY),
            topRight: CGPoint(x: size.width - insetX, y: size.height - insetY),
            bottomLeft: CGPoint(x: insetX, y: insetY),
            bottomRight: CGPoint(x: size.width - insetX, y: insetY)
        )
    }

    // MARK: Panning

    /// Pans the crop from a drag over the corrected preview. `delta` is in
    /// display points; the preview shown is the corrected downscaled
    /// render aspect-fitted to `previewFittedWidth`. The painting follows
    /// the finger, so the crop window moves the opposite way — and the
    /// display y-axis points down while canonical y points up.
    func pan(byDisplayDelta delta: CGSize, previewFittedWidth: CGFloat) {
        guard let previewImage, previewScale > 0, previewFittedWidth > 0 else { return }
        let displayToSource = CGFloat(previewImage.width) / previewFittedWidth / previewScale
        panOffset.dx -= delta.width * displayToSource
        panOffset.dy += delta.height * displayToSource
        regeneratePreview()
    }

    func resetPan() {
        guard isPanned else { return }
        panOffset = .zero
        regeneratePreview()
    }

    // MARK: Corner adjustment

    func moveCorner(_ corner: Quad.Corner, toDisplayPoint point: CGPoint, mapper: DisplayMapper) {
        guard var quad else { return }
        let pixel = mapper.pixelPoint(fromDisplay: point)
        let bounds = CGRect(origin: .zero, size: imagePixelSize)
        quad[corner] = CGPoint(
            x: min(max(pixel.x, bounds.minX), bounds.maxX),
            y: min(max(pixel.y, bounds.minY), bounds.maxY)
        )
        self.quad = quad
        regeneratePreview()
    }

    // MARK: Preview

    /// Debounced: a new call cancels the queued render, and a short sleep
    /// before rendering means a slider drag produces one render per beat
    /// instead of one per tick.
    func regeneratePreview() {
        guard showCorrectedPreview else { return }
        guard let previewBase, let quad else { return }
        previewTask?.cancel()
        let margin = CGFloat(marginPixels)
        let scale = previewScale
        let pan = panOffset
        let pipeline = pipeline
        isRenderingPreview = true
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                pipeline.previewImage(
                    downscaled: previewBase,
                    scaleFromFullRes: scale,
                    quad: quad,
                    marginPixels: margin,
                    panOffset: pan
                )
            }.value
            guard !Task.isCancelled else { return }
            previewImage = rendered
            isRenderingPreview = false
        }
    }

    // MARK: Export

    func export() async {
        guard let sourceImage, let quad else { return }
        stage = .exporting
        errorMessage = nil
        exportDenied = false
        let margin = CGFloat(marginPixels)
        let pan = panOffset
        let pipeline = pipeline
        let rendered = await Task.detached(priority: .userInitiated) {
            pipeline.finalImage(
                fullResImage: sourceImage,
                quad: quad,
                marginPixels: margin,
                panOffset: pan
            )
        }.value
        guard let rendered else {
            errorMessage = "Rendering failed — try adjusting the corners."
            stage = .adjusting
            return
        }
        do {
            try await exporter.export(rendered)
            stage = .exported
        } catch PhotoLibraryExporter.ExportError.notAuthorized {
            errorMessage = "Allow photo access in Settings to save."
            exportDenied = true
            stage = .adjusting
        } catch {
            errorMessage = "Saving failed. Please try again."
            stage = .adjusting
        }
    }

    // MARK: Reset

    func reset() {
        loadTask?.cancel()
        previewTask?.cancel()
        selection = nil
        sourceImage = nil
        quad = nil
        previewImage = nil
        previewBase = nil
        previewScale = 1
        panOffset = .zero
        detectionFailed = false
        exportDenied = false
        showCorrectedPreview = false
        errorMessage = nil
        stage = .picking
    }
}
