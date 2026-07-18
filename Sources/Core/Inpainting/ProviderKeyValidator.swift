import Foundation

/// Cheap authenticated GET per provider — verifies a key without paying
/// for a generation.
struct ProviderKeyValidator: Sendable {
    var session: URLSession = .shared

    func validate(provider: AIProvider, apiKey: String) async -> Bool {
        var request: URLRequest
        switch provider {
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
