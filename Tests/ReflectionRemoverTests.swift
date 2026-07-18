import CoreGraphics
import Testing
@testable import PictureFramer

/// Provider double: records what it was asked, returns a solid image at
/// the requested upload size.
private final class MockProvider: InpaintingProvider, @unchecked Sendable {
    var receivedImageSize: CGSize?
    var receivedMaskSize: CGSize?
    var resultGray: CGFloat = 1.0
    var errorToThrow: InpaintingError?

    func uploadSize(for cropSize: CGSize) -> CGSize {
        CGSize(width: 256, height: 256)   // fixed, aspect-distorting on purpose
    }

    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
        if let errorToThrow { throw errorToThrow }
        receivedImageSize = CGSize(width: image.width, height: image.height)
        receivedMaskSize = CGSize(width: mask.width, height: mask.height)
        return FixtureImageFactory.solidImage(
            size: CGSize(width: image.width, height: image.height), gray: resultGray)
    }
}

@Suite struct ReflectionRemoverTests {

    private let size = CGSize(width: 640, height: 480)
    private let remover = ReflectionRemover()

    private func maskWithBlob(at center: CGPoint, radius: CGFloat) -> ReflectionMask {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: radius, points: [center]))
        return mask
    }

    @Test func emptyMaskThrows() async {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 1)
        await #expect(throws: InpaintingError.emptyMask) {
            _ = try await remover.remove(
                from: image, mask: ReflectionMask(imageSize: size),
                provider: MockProvider(), apiKey: "k")
        }
    }

    @Test func cropIsResizedToProviderUploadSize() async throws {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 2)
        let provider = MockProvider()
        _ = try await remover.remove(
            from: image, mask: maskWithBlob(at: CGPoint(x: 320, y: 240), radius: 60),
            provider: provider, apiKey: "k")
        #expect(provider.receivedImageSize == CGSize(width: 256, height: 256))
        #expect(provider.receivedMaskSize == CGSize(width: 256, height: 256))
    }

    @Test func resultChangesOnlyInsideMask() async throws {
        let image = FixtureImageFactory.solidImage(size: size, gray: 0.2)
        let mask = maskWithBlob(at: CGPoint(x: 320, y: 240), radius: 60)
        let provider = MockProvider()
        provider.resultGray = 1.0
        let result = try await remover.remove(
            from: image, mask: mask, provider: provider, apiKey: "k")
        #expect(result.width == Int(size.width) && result.height == Int(size.height))
        let sampler = PixelSampler(image: result)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 320, y: 240)) > 0.9)  // repainted
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 50, y: 50)) < 0.3)    // untouched
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 600, y: 440)) < 0.3)  // untouched
    }

    @Test func maskCoveringWholeImageStillWorks() async throws {
        let image = FixtureImageFactory.solidImage(size: size, gray: 0.2)
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 500, points: [CGPoint(x: 320, y: 240)]))
        let result = try await remover.remove(
            from: image, mask: mask, provider: MockProvider(), apiKey: "k")
        let sampler = PixelSampler(image: result)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 320, y: 240)) > 0.9)
    }

    @Test func providerErrorPropagates() async {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 3)
        let provider = MockProvider()
        provider.errorToThrow = .rateLimited
        await #expect(throws: InpaintingError.rateLimited) {
            _ = try await remover.remove(
                from: image, mask: maskWithBlob(at: CGPoint(x: 320, y: 240), radius: 60),
                provider: provider, apiKey: "k")
        }
    }

    @Test func tinyImageDoesNotCrash() async throws {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 4, height: 4), gray: 0.2)
        var mask = ReflectionMask(imageSize: CGSize(width: 4, height: 4))
        mask.add(.init(mode: .add, radius: 3, points: [CGPoint(x: 2, y: 2)]))
        let result = try await remover.remove(
            from: image, mask: mask, provider: MockProvider(), apiKey: "k")
        #expect(result.width == 4 && result.height == 4)
    }
}
