import Foundation

/// Seam over secret persistence so tests never touch the real Keychain.
protocol SecretStoring: Sendable {
    /// nil value deletes the secret.
    func setSecret(_ value: String?, forKey key: String) throws
    func secret(forKey key: String) throws -> String?
}

final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func setSecret(_ value: String?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func secret(forKey key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
}
