import Foundation

/// Cloud inpainting providers the user can configure in Settings.
enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAI
    case gemini

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        }
    }
}
