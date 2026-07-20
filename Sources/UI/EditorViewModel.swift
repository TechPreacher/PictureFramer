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
        case reflection
        case exporting
        case exported
    }

    var stage: Stage = .picking

    /// Whether the crop keeps the frame + wall margin or just the painting.
    /// Persisted; switching with a photo loaded re-runs detection because
    /// the target quad (frame edge vs painting edge) changes wholesale.
    var cropMode: CropMode {
        didSet {
            guard cropMode != oldValue else { return }
            defaults.set(cropMode.rawValue, forKey: Self.cropModeKey)
            guard sourceImage != nil else { return }
            invalidateCleaned()
            detectionTask = Task { await runDetection() }
        }
    }
    /// Re-detection spawned by a mode switch; exposed so tests can await it.
    private(set) var detectionTask: Task<Void, Never>?

    /// Margin actually applied to rendering and detection — painting-only
    /// mode crops the frame away, so a wall margin never applies there.
    /// The slider value itself survives mode round trips.
    var effectiveMarginPixels: Double {
        cropMode == .paintingOnly ? 0 : marginPixels
    }

    private static let cropModeKey = "cropMode"
    private let defaults: UserDefaults

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
        didSet { invalidateCleaned(); regeneratePreview() }
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

    // MARK: Reflection removal state

    /// Full-res corrected render the reflection mask refers to. Canonical
    /// space for the mask = this image's pixels, lower-left origin.
    private(set) var correctedFullRes: CGImage?
    var reflectionMask: ReflectionMask?
    /// Accepted AI result — exported verbatim instead of re-rendering.
    private(set) var cleanedImage: CGImage?
    /// AI result awaiting user accept/reject in the compare view.
    private(set) var pendingCleaned: CGImage?
    private(set) var isRemovingReflections = false
    /// Bumped whenever reflection state is torn down; in-flight async
    /// reflection work checks it before writing results back.
    private var reflectionGeneration = 0

    /// Mirrors `settings.isConfigured` as an observable property — the
    /// settings store itself isn't `@Observable`, so views must go through
    /// this and call `refreshProviderConfiguration()` after the settings
    /// sheet dismisses.
    private(set) var isProviderConfigured = false

    let settings: ProviderSettingsStore
    private let reflectionDetector: ReflectionMaskDetector
    private let remover: ReflectionRemover
    private let inpainterFactory: @Sendable (AIProvider) -> any InpaintingProvider

    private let pipeline: FramingPipeline
    private let exporter: PhotoLibraryExporter
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// Downscaled copy of the source, computed once per photo — interactive
    /// preview renders reuse it instead of re-downscaling the full-res
    /// image on every slider tick.
    private var previewBase: CGImage?
    private var previewScale: CGFloat = 1

    init(
        pipeline: FramingPipeline = FramingPipeline(),
        exporter: PhotoLibraryExporter = PhotoLibraryExporter(),
        settings: ProviderSettingsStore = ProviderSettingsStore(),
        detector: ReflectionMaskDetector = ReflectionMaskDetector(),
        remover: ReflectionRemover = ReflectionRemover(),
        inpainterFactory: @escaping @Sendable (AIProvider) -> any InpaintingProvider = {
            $0.makeInpainter()
        },
        defaults: UserDefaults = .standard
    ) {
        self.pipeline = pipeline
        self.exporter = exporter
        self.settings = settings
        self.reflectionDetector = detector
        self.remover = remover
        self.inpainterFactory = inpainterFactory
        self.isProviderConfigured = settings.isConfigured
        self.defaults = defaults
        self.cropMode =
            CropMode(rawValue: defaults.string(forKey: Self.cropModeKey) ?? "") ?? .framed
    }

    /// Call after the settings sheet dismisses so the AI-provider-dependent
    /// UI (e.g. the "Remove Reflections" button) reflects the latest keys.
    func refreshProviderConfiguration() {
        isProviderConfigured = settings.isConfigured
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
            marginPixels: CGFloat(effectiveMarginPixels),
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
        invalidateCleaned()
        detectionFailed = false
        panOffset = .zero
        do {
            if let detected = try await pipeline.detectQuad(in: sourceImage, mode: cropMode) {
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
        invalidateCleaned()
        let displayToSource = CGFloat(previewImage.width) / previewFittedWidth / previewScale
        panOffset.dx -= delta.width * displayToSource
        panOffset.dy += delta.height * displayToSource
        regeneratePreview()
    }

    func resetPan() {
        guard isPanned else { return }
        invalidateCleaned()
        panOffset = .zero
        regeneratePreview()
    }

    // MARK: Corner adjustment

    func moveCorner(_ corner: Quad.Corner, toDisplayPoint point: CGPoint, mapper: DisplayMapper) {
        guard var quad else { return }
        invalidateCleaned()
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
        // An accepted AI result should preview as-is, not as a fresh
        // (glare-y) re-render of the source through the pipeline.
        if let cleanedImage {
            previewTask?.cancel()
            isRenderingPreview = true
            previewTask = Task {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                let rendered = await Task.detached(priority: .userInitiated) {
                    downscaled(cleanedImage, maxDimension: 1600)
                }.value
                guard !Task.isCancelled else { return }
                previewImage = rendered
                isRenderingPreview = false
            }
            return
        }
        guard let previewBase, let quad else { return }
        previewTask?.cancel()
        let margin = CGFloat(effectiveMarginPixels)
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

    // MARK: Reflection removal

    /// Renders the full-res corrected image and enters the reflection
    /// stage with an EMPTY mask — auto-detection is opt-in via the
    /// Auto-detect button (`redetectReflections`).
    func beginReflectionRemoval() async {
        guard let sourceImage, let quad else { return }
        errorMessage = nil
        let generation = reflectionGeneration

        // Crop params can't have drifted since the last accept — any crop
        // change nils cleanedImage via invalidateCleaned. Reuse it as the
        // working image instead of re-rendering (which would reintroduce
        // the glare that was just painted out).
        // Auto-detection is opt-in (Auto-detect button) — the mask starts
        // empty so the user is never greeted by unwanted proposals.
        if let cleanedImage {
            correctedFullRes = cleanedImage
            reflectionMask = ReflectionMask(
                imageSize: CGSize(width: cleanedImage.width, height: cleanedImage.height)
            )
            pendingCleaned = nil
            stage = .reflection
            return
        }

        let margin = CGFloat(effectiveMarginPixels)
        let pan = panOffset
        let pipeline = pipeline
        let corrected = await Task.detached(priority: .userInitiated) {
            pipeline.finalImage(
                fullResImage: sourceImage, quad: quad,
                marginPixels: margin, panOffset: pan
            )
        }.value
        guard generation == reflectionGeneration else { return }
        guard let corrected else {
            errorMessage = "Rendering failed — try adjusting the corners."
            return
        }
        correctedFullRes = corrected
        reflectionMask = ReflectionMask(
            imageSize: CGSize(width: corrected.width, height: corrected.height)
        )
        pendingCleaned = nil
        stage = .reflection
    }

    func redetectReflections() {
        guard let correctedFullRes, var mask = reflectionMask else { return }
        mask.detectedRaster = reflectionDetector.detectMask(
            in: correctedFullRes, excludingBorder: CGFloat(effectiveMarginPixels))
        reflectionMask = mask
    }

    func addMaskStroke(_ stroke: ReflectionMask.Stroke) {
        reflectionMask?.add(stroke)
    }

    /// Drops the detector proposal and every brush stroke in one go.
    func clearReflectionMask() {
        reflectionMask?.clear()
    }

    func runReflectionRemoval() async {
        guard !isRemovingReflections else { return }
        guard let correctedFullRes, let mask = reflectionMask else { return }
        guard let provider = settings.selectedProvider,
              let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty else {
            errorMessage = "Set up an AI provider in Settings first."
            return
        }
        guard !mask.isEmpty else {
            errorMessage = "Mark at least one reflection to remove."
            return
        }
        errorMessage = nil
        isRemovingReflections = true
        defer { isRemovingReflections = false }
        let generation = reflectionGeneration
        do {
            let cleaned = try await remover.remove(
                from: correctedFullRes,
                mask: mask,
                provider: inpainterFactory(provider),
                apiKey: apiKey
            )
            guard generation == reflectionGeneration else { return }
            pendingCleaned = cleaned
        } catch InpaintingError.invalidKey {
            guard generation == reflectionGeneration else { return }
            errorMessage = "The API key was rejected — check it in Settings."
        } catch let InpaintingError.rateLimited(detail) {
            guard generation == reflectionGeneration else { return }
            if let detail {
                errorMessage = "Rate-limited by the provider: \(detail)"
            } else {
                errorMessage = "The provider is rate-limiting — try again shortly."
            }
        } catch InpaintingError.emptyMask {
            guard generation == reflectionGeneration else { return }
            errorMessage = "Mark at least one reflection to remove."
        } catch let InpaintingError.server(message) {
            guard generation == reflectionGeneration else { return }
            errorMessage = "Provider error: \(message)"
        } catch {
            guard generation == reflectionGeneration else { return }
            errorMessage = "Reflection removal failed. Check your connection and try again."
        }
    }

    func acceptCleaned() {
        guard let pendingCleaned else { return }
        cleanedImage = pendingCleaned
        self.pendingCleaned = nil
        stage = .adjusting
        showCorrectedPreview = true
    }

    func discardPendingCleaned() {
        pendingCleaned = nil
    }

    func exitReflectionRemoval() {
        reflectionGeneration += 1
        correctedFullRes = nil
        reflectionMask = nil
        pendingCleaned = nil
        errorMessage = nil
        isRemovingReflections = false
        stage = .adjusting
    }

    /// Any change to the crop makes an accepted AI result stale.
    private func invalidateCleaned() {
        reflectionGeneration += 1
        cleanedImage = nil
        correctedFullRes = nil
        reflectionMask = nil
        pendingCleaned = nil
    }

    // MARK: Export

    func export() async {
        // Kill any in-flight reflection-removal continuation so a late
        // render can't yank stage back out of .exporting.
        reflectionGeneration += 1
        guard let sourceImage, let quad else { return }
        stage = .exporting
        errorMessage = nil
        exportDenied = false
        let rendered: CGImage?
        if let cleanedImage {
            rendered = cleanedImage
        } else {
            let margin = CGFloat(effectiveMarginPixels)
            let pan = panOffset
            let pipeline = pipeline
            rendered = await Task.detached(priority: .userInitiated) {
                pipeline.finalImage(
                    fullResImage: sourceImage,
                    quad: quad,
                    marginPixels: margin,
                    panOffset: pan
                )
            }.value
        }
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
        detectionTask?.cancel()
        detectionTask = nil
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
        invalidateCleaned()
        stage = .picking
    }

    // MARK: Test support

    /// Injects a source image + quad without the photo picker. Test-only.
    func setSourceForTesting(_ image: CGImage, quad: Quad) {
        sourceImage = image
        self.quad = quad
        stage = .adjusting
    }
}
