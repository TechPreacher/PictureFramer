import Foundation
import Testing
@testable import PictureFramer

@Suite struct ProviderSettingsTests {

    private func makeStore() -> (ProviderSettingsStore, UserDefaults, InMemorySecretStore) {
        let defaults = UserDefaults(suiteName: "ProviderSettingsTests-\(UUID().uuidString)")!
        let secrets = InMemorySecretStore()
        return (ProviderSettingsStore(defaults: defaults, secrets: secrets), defaults, secrets)
    }

    @Test func selectedProviderRoundTrips() {
        let (store, _, _) = makeStore()
        #expect(store.selectedProvider == nil)
        store.selectedProvider = .gemini
        #expect(store.selectedProvider == .gemini)
        store.selectedProvider = nil
        #expect(store.selectedProvider == nil)
    }

    @Test func apiKeyRoundTripsPerProvider() {
        let (store, _, _) = makeStore()
        store.setAPIKey("sk-open", for: .openAI)
        store.setAPIKey("gm-key", for: .gemini)
        #expect(store.apiKey(for: .openAI) == "sk-open")
        #expect(store.apiKey(for: .gemini) == "gm-key")
        store.setAPIKey(nil, for: .openAI)
        #expect(store.apiKey(for: .openAI) == nil)
    }

    @Test func secretsNeverTouchUserDefaults() {
        let (store, defaults, _) = makeStore()
        store.setAPIKey("sk-supersecret-123", for: .openAI)
        let values = defaults.dictionaryRepresentation().values.map { "\($0)" }
        #expect(!values.contains { $0.contains("sk-supersecret-123") })
    }

    @Test func isConfiguredRequiresProviderAndKey() {
        let (store, _, _) = makeStore()
        #expect(!store.isConfigured)
        store.selectedProvider = .openAI
        #expect(!store.isConfigured)
        store.setAPIKey("sk-x", for: .openAI)
        #expect(store.isConfigured)
        store.setAPIKey("", for: .openAI)
        #expect(!store.isConfigured)
    }

    @Test func keychainStoreRoundTrips() throws {
        let store = KeychainStore(service: "com.corti.PictureFramer.tests")
        try store.setSecret("hunter2", forKey: "unit-test-key")
        #expect(try store.secret(forKey: "unit-test-key") == "hunter2")
        try store.setSecret(nil, forKey: "unit-test-key")
        #expect(try store.secret(forKey: "unit-test-key") == nil)
    }
}
