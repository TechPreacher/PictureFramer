import Foundation

/// Non-secret settings in UserDefaults, API keys in the secret store.
final class ProviderSettingsStore: @unchecked Sendable {
    private static let providerKey = "selectedAIProvider"

    private let defaults: UserDefaults
    private let secrets: any SecretStoring

    init(defaults: UserDefaults = .standard, secrets: any SecretStoring = KeychainStore()) {
        self.defaults = defaults
        self.secrets = secrets
    }

    var selectedProvider: AIProvider? {
        get { defaults.string(forKey: Self.providerKey).flatMap(AIProvider.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Self.providerKey) }
    }

    func apiKey(for provider: AIProvider) -> String? {
        (try? secrets.secret(forKey: "apiKey.\(provider.rawValue)")) ?? nil
    }

    func setAPIKey(_ key: String?, for provider: AIProvider) {
        try? secrets.setSecret(key, forKey: "apiKey.\(provider.rawValue)")
    }

    /// True when a provider is chosen AND it has a non-empty key.
    var isConfigured: Bool {
        guard let provider = selectedProvider,
              let key = apiKey(for: provider) else { return false }
        return !key.isEmpty
    }
}
