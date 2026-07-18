import CoreGraphics
import Foundation

/// Gemini image editing via generateContent. Gemini has no native mask
/// parameter, so the mask goes along as a second inline image with strict
/// prompt instructions; PatchCompositor still enforces that only masked
/// pixels change regardless of what the model returns.
struct GeminiInpainter: InpaintingProvider {
    var session: URLSession = .shared
    var model: String = "gemini-2.5-flash-image"

    func uploadSize(for cropSize: CGSize) -> CGSize {
        let maxDimension: CGFloat = 1024
        let largest = max(cropSize.width, cropSize.height)
        guard largest > maxDimension else { return cropSize }
        let scale = maxDimension / largest
        return CGSize(
            width: (cropSize.width * scale).rounded(),
            height: (cropSize.height * scale).rounded()
        )
    }

    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
        guard let imagePNG = pngData(from: image), let maskPNG = pngData(from: mask) else {
            throw InpaintingError.renderingFailed
        }
        let prompt = InpaintingPrompt.text + """
             The second image is the mask: repaint only areas that are \
            white in the mask.
            """
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/png",
                                     "data": imagePNG.base64EncodedString()]],
                    ["inline_data": ["mime_type": "image/png",
                                     "data": maskPNG.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["responseModalities": ["IMAGE"]],
        ]
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try OpenAIInpainter.checkStatus(response: response, data: data)

        struct Payload: Decodable {
            struct Candidate: Decodable { let content: Content }
            struct Content: Decodable { let parts: [Part] }
            struct Part: Decodable { let inlineData: InlineData? }
            struct InlineData: Decodable { let data: String }
            let candidates: [Candidate]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let b64 = payload.candidates.first?.content.parts
                .compactMap(\.inlineData).first?.data,
              let imageData = Data(base64Encoded: b64),
              let result = cgImage(fromEncoded: imageData) else {
            throw InpaintingError.invalidResponse
        }
        return result
    }
}
