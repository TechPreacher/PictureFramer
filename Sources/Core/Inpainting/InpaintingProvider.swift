import CoreGraphics
import Foundation

enum InpaintingError: Error, Equatable {
    case notConfigured
    case invalidKey
    /// HTTP 429. `detail` carries the provider's own explanation when the
    /// body has one — for Gemini free-tier keys the image model 429s
    /// permanently ("exceeded your current quota"), and without the detail
    /// that's indistinguishable from a transient rate limit.
    case rateLimited(detail: String?)
    case invalidResponse
    case server(String)
    case emptyMask
    case renderingFailed
}

/// A cloud service that repaints white-masked regions of an image.
protocol InpaintingProvider: Sendable {
    /// Pixel size the crop is resized to before upload. May change aspect;
    /// the caller resizes the result back so the distortion cancels.
    func uploadSize(for cropSize: CGSize) -> CGSize
    /// `mask` is grayscale, same size as `image`, white = repaint.
    /// The returned image may be any size; the caller rescales.
    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage
}

enum InpaintingPrompt {
    static let text = """
        This is a photograph of a painting. The masked region contains a \
        glass reflection or glare. Remove the reflection and reconstruct \
        the artwork underneath, matching the surrounding brushwork, colors, \
        texture and lighting exactly. Change nothing outside the masked \
        region. Return only the edited image.
        """
}

extension AIProvider {
    func makeInpainter(session: URLSession = .shared) -> any InpaintingProvider {
        switch self {
        case .openAI: OpenAIInpainter(session: session)
        case .gemini: GeminiInpainter(session: session)
        }
    }
}
