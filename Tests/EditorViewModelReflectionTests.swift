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
        #expect(model.stage == .picking)
    }
}
