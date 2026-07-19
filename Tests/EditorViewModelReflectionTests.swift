import CoreGraphics
import Foundation
import Testing
@testable import PictureFramer

@MainActor
@Suite struct EditorViewModelReflectionTests {

    private final class RecordingProvider: InpaintingProvider, @unchecked Sendable {
        var callCount = 0
        func uploadSize(for cropSize: CGSize) -> CGSize { cropSize }
        func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
            callCount += 1
            return FixtureImageFactory.solidImage(
                size: CGSize(width: image.width, height: image.height), gray: 1.0)
        }
    }

    /// Model with a loaded fixture "photo" and detected quad, configured
    /// provider, and a recording inpainter.
    private func makeModel(provider: RecordingProvider = RecordingProvider())
    -> (EditorViewModel, ProviderSettingsStore) {
        let defaults = UserDefaults(suiteName: "EditorVMReflection-\(UUID().uuidString)")!
        let settings = ProviderSettingsStore(defaults: defaults, secrets: InMemorySecretStore())
        settings.selectedProvider = .openAI
        settings.setAPIKey("sk-test", for: .openAI)
        let model = EditorViewModel(
            settings: settings,
            inpainterFactory: { _ in provider }
        )
        let size = CGSize(width: 800, height: 600)
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 100)
        model.setSourceForTesting(
            FixtureImageFactory.image(size: size, quad: quad), quad: quad)
        return (model, settings)
    }

    @Test func beginReflectionRemovalRendersCorrectedAndEntersStage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        #expect(model.stage == .reflection)
        #expect(model.correctedFullRes != nil)
        #expect(model.reflectionMask != nil)   // present (possibly empty of strokes)
    }

    /// Auto-detection is opt-in: entering the stage proposes nothing; the
    /// Auto-detect button (redetectReflections) runs the detector on demand.
    @Test func beginReflectionRemovalStartsWithEmptyMask() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        #expect(model.reflectionMask?.detectedRaster == nil)
        #expect(model.reflectionMask?.isEmpty == true)
    }

    @Test func runReflectionRemovalProducesPendingResult() async {
        let provider = RecordingProvider()
        let (model, _) = makeModel(provider: provider)
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        #expect(provider.callCount == 1)
        #expect(model.pendingCleaned != nil)
        #expect(model.cleanedImage == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func acceptPendingMakesItTheCleanedImage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        model.acceptCleaned()
        #expect(model.cleanedImage != nil)
        #expect(model.pendingCleaned == nil)
        #expect(model.stage == .adjusting)
    }

    @Test func secondRemovalRoundStartsFromCleanedImage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        model.acceptCleaned()
        #expect(model.cleanedImage != nil)

        // A second round should reuse the accepted image (with the mask
        // area painted white by RecordingProvider) as the working base
        // instead of re-rendering the glare-y source from scratch.
        await model.beginReflectionRemoval()
        #expect(model.stage == .reflection)
        let corrected = model.correctedFullRes
        #expect(corrected != nil)
        guard let corrected else { return }
        let sampler = PixelSampler(image: corrected)
        // Sample points well inside the 40-radius stroke centered at
        // (300, 200) — the region the first round painted white.
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 300, y: 200)) > 0.9)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 310, y: 205)) > 0.9)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 290, y: 195)) > 0.9)
    }

    @Test func clearReflectionMaskEmptiesProposalAndStrokes() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        #expect(model.reflectionMask?.isEmpty == false)
        model.clearReflectionMask()
        #expect(model.reflectionMask?.isEmpty == true)
        #expect(model.reflectionMask?.detectedRaster == nil)
        #expect(model.reflectionMask?.strokes.isEmpty == true)
    }

    @Test func emptyMaskRemovalSetsError() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.reflectionMask?.clear()
        await model.runReflectionRemoval()
        #expect(model.pendingCleaned == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func unconfiguredProviderSetsError() async {
        let (model, settings) = makeModel()
        settings.selectedProvider = nil
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        #expect(model.pendingCleaned == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func adjustingQuadInvalidatesCleanedImage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        model.acceptCleaned()
        #expect(model.cleanedImage != nil)
        model.marginPixels = 80   // changes the crop — cleaned image is stale
        #expect(model.cleanedImage == nil)
    }

    @Test func resetClearsReflectionState() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.reset()
        #expect(model.correctedFullRes == nil)
        #expect(model.reflectionMask == nil)
        #expect(model.cleanedImage == nil)
        #expect(model.pendingCleaned == nil)
        #expect(model.isRemovingReflections == false)
        #expect(model.stage == .picking)
    }

    /// Provider that blocks until the test releases it.
    private final class GatedProvider: InpaintingProvider, @unchecked Sendable {
        let gate = AsyncStream<Void>.makeStream()
        func uploadSize(for cropSize: CGSize) -> CGSize { cropSize }
        func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
            var iterator = gate.stream.makeAsyncIterator()
            _ = await iterator.next()
            return FixtureImageFactory.solidImage(
                size: CGSize(width: image.width, height: image.height), gray: 1.0)
        }
    }

    @Test func exitDuringRemovalDropsLateResult() async {
        let provider = GatedProvider()
        let defaults = UserDefaults(suiteName: "EditorVMReflection-\(UUID().uuidString)")!
        let settings = ProviderSettingsStore(defaults: defaults, secrets: InMemorySecretStore())
        settings.selectedProvider = .openAI
        settings.setAPIKey("sk-test", for: .openAI)
        let model = EditorViewModel(
            settings: settings,
            inpainterFactory: { _ in provider }
        )
        let size = CGSize(width: 800, height: 600)
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 100)
        model.setSourceForTesting(
            FixtureImageFactory.image(size: size, quad: quad), quad: quad)

        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40, points: [CGPoint(x: 300, y: 200)]))
        let removal = Task { await model.runReflectionRemoval() }
        // Let the removal task reach the gate.
        for _ in 0..<5 {
            await Task.yield()
        }
        model.exitReflectionRemoval()
        provider.gate.continuation.yield()      // release the provider
        provider.gate.continuation.finish()
        await removal.value
        #expect(model.pendingCleaned == nil)    // late result dropped
        #expect(model.stage == .adjusting)
    }
}
