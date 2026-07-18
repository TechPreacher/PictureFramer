import CoreGraphics
import Foundation
import Testing
@testable import PictureFramer

extension NetworkStubSuites {

@Suite struct GeminiInpainterTests {

    private let image = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.4)
    private let mask = ReflectionMask.grayImage(
        from: [UInt8](repeating: 255, count: 64 * 64), width: 64, height: 64)!

    private func inpainter() -> GeminiInpainter {
        GeminiInpainter(session: StubURLProtocol.session())
    }

    @Test func uploadSizeCapsLongestSideAt1024PreservingAspect() {
        let sut = inpainter()
        #expect(sut.uploadSize(for: CGSize(width: 2048, height: 1024)) == CGSize(width: 1024, height: 512))
        #expect(sut.uploadSize(for: CGSize(width: 500, height: 400)) == CGSize(width: 500, height: 400))
    }

    @Test func sendsGenerateContentAndDecodesInlineImage() async throws {
        let returned = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.9)
        let b64 = pngData(from: returned)!.base64EncodedString()
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString ==
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gm-test")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let json = try! JSONSerialization.jsonObject(
                with: request.httpBody ?? Data()) as! [String: Any]
            let contents = json["contents"] as! [[String: Any]]
            let parts = contents[0]["parts"] as! [[String: Any]]
            #expect(parts.count == 3)   // prompt text + image + mask
            #expect(parts[0]["text"] is String)
            let response = #"""
            {"candidates":[{"content":{"parts":[
              {"text":"done"},
              {"inlineData":{"mimeType":"image/png","data":"\#(b64)"}}
            ]}}]}
            """#
            return (200, Data(response.utf8))
        }
        let result = try await inpainter().inpaint(image: image, mask: mask, apiKey: "gm-test")
        #expect(result.width == 64 && result.height == 64)
    }

    @Test func responseWithoutImageIsInvalidResponse() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"no can do"}]}}]}"#.utf8))
        }
        await #expect(throws: InpaintingError.invalidResponse) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "gm-test")
        }
    }

    @Test func maps403ToInvalidKey() async {
        StubURLProtocol.handler = { _ in (403, Data()) }
        await #expect(throws: InpaintingError.invalidKey) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "gm-bad")
        }
    }

    @Test func factoryMakesMatchingInpainter() {
        #expect(AIProvider.openAI.makeInpainter() is OpenAIInpainter)
        #expect(AIProvider.gemini.makeInpainter() is GeminiInpainter)
    }
}

}
