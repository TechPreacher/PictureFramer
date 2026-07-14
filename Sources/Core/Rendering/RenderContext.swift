import CoreImage

/// One CIContext for the whole app — contexts are expensive to create and
/// thread-safe to share.
final class RenderContext: Sendable {
    static let shared = RenderContext()

    let ciContext: CIContext

    init() {
        ciContext = CIContext(options: [.cacheIntermediates: false])
    }

    func makeCGImage(from image: CIImage) -> CGImage? {
        ciContext.createCGImage(image, from: image.extent)
    }
}
