import Foundation
import Security
import Synchronization

/// Where secrets (IGDB credentials, the Twitch token, the Hasheous key) are kept.
public protocol SecretStore: Sendable {
    func secret(for key: String) throws -> String?
    /// Stores a secret, or removes it when `value` is nil.
    func setSecret(_ value: String?, for key: String) throws
}

/// Generic passwords in the login Keychain. Access survives rebuilds only with a stable
/// signing identity: an ad-hoc signed app is asked for Keychain access again after each one.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "org.danielholmes.GamesJournal") { self.service = service }

    public func secret(for key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func setSecret(_ value: String?, for key: String) throws {
        guard let value else {
            let status = SecItemDelete(baseQuery(key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(baseQuery(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}

/// Secrets in memory only, for tests and previews.
public final class InMemorySecretStore: SecretStore {
    private let secrets = Mutex<[String: String]>([:])

    public init() {}

    public func secret(for key: String) throws -> String? { secrets.withLock { $0[key] } }
    public func setSecret(_ value: String?, for key: String) throws { secrets.withLock { $0[key] = value } }
}
