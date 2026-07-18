import CoreGraphics
import Foundation
import Testing
@testable import PictureFramer

@Suite(.serialized) struct OpenAIInpainterTests {

    private let image = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.4)
    private let mask = ReflectionMask.grayImage(
        from: [UInt8](repeating: 255, count: 64 * 64), width: 64, height: 64)!

    private func inpainter() -> OpenAIInpainter {
        OpenAIInpainter(session: StubURLProtocol.session())
    }

    @Test func uploadSizePicksNearestAspect() {
        let sut = inpainter()
        #expect(sut.uploadSize(for: CGSize(width: 500, height: 480)) == CGSize(width: 1024, height: 1024))
        #expect(sut.uploadSize(for: CGSize(width: 900, height: 500)) == CGSize(width: 1536, height: 1024))
        #expect(sut.uploadSize(for: CGSize(width: 400, height: 800)) == CGSize(width: 1024, height: 1536))
    }

    @Test func sendsMultipartEditRequestAndDecodesImage() async throws {
        let returned = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.9)
        let b64 = pngData(from: returned)!.base64EncodedString()
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("name=\"model\""))
            #expect(body.contains("gpt-image-1"))
            #expect(body.contains("name=\"image[]\""))
            #expect(body.contains("name=\"mask\""))
            #expect(body.contains("name=\"prompt\""))
            let json = #"{"data":[{"b64_json":"\#(b64)"}]}"#
            return (200, Data(json.utf8))
        }
        let result = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        #expect(result.width == 64 && result.height == 64)
    }

    @Test func maps401ToInvalidKey() async {
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":{"message":"bad key"}}"#.utf8)) }
        await #expect(throws: InpaintingError.invalidKey) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-bad")
        }
    }

    @Test func maps429ToRateLimited() async {
        StubURLProtocol.handler = { _ in (429, Data()) }
        await #expect(throws: InpaintingError.rateLimited) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        }
    }

    @Test func mapsMalformedJSONToInvalidResponse() async {
        StubURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
        await #expect(throws: InpaintingError.invalidResponse) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        }
    }

    @Test func mapsServerErrorWithMessage() async {
        StubURLProtocol.handler = { _ in
            (500, Data(#"{"error":{"message":"boom"}}"#.utf8))
        }
        await #expect(throws: InpaintingError.server("boom")) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        }
    }
}
