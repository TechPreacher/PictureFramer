import Foundation
import Testing
@testable import PictureFramer

extension NetworkStubSuites {

@Suite struct ProviderKeyValidatorTests {

    private func validator() -> ProviderKeyValidator {
        ProviderKeyValidator(session: StubURLProtocol.session())
    }

    @Test func openAIValidationHitsModelsEndpoint() async {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ok")
            return (200, Data("{}".utf8))
        }
        #expect(await validator().validate(provider: .openAI, apiKey: "sk-ok"))
    }

    @Test func geminiValidationHitsModelsEndpoint() async {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString ==
                "https://generativelanguage.googleapis.com/v1beta/models")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gm-ok")
            return (200, Data("{}".utf8))
        }
        #expect(await validator().validate(provider: .gemini, apiKey: "gm-ok"))
    }

    @Test func badKeyFailsValidation() async {
        StubURLProtocol.handler = { _ in (401, Data()) }
        #expect(!(await validator().validate(provider: .openAI, apiKey: "sk-bad")))
    }
}

}
