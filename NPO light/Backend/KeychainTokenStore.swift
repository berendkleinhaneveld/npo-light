//
//  KeychainTokenStore.swift
//  NPO light
//

import Foundation
import Security

/// The session, kept in the Keychain (FR-AUTH-02, NFR-PRIV-02).
///
/// On a real Apple TV this is the only place it survives: `Documents` and
/// `Application Support` are read-only there, and what is left is evictable
/// (ADR 0007).
nonisolated struct KeychainTokenStore: TokenStore {
    static let defaultService = "com.bearduck.NPO-light.session"

    private static let account = "default"

    private let service: String

    /// - Parameter service: the Keychain service the item is filed under. Tests
    ///   pass a name of their own, so that runs do not meet each other's items
    ///   (ADR 0009).
    init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    func load() throws -> Session? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandled(status: status)
        }
        // An item this app can no longer read is no session, and saying so
        // leads to sign-in rather than to an error nobody can act on.
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(itemQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = itemQuery
            item[kSecValueData as String] = data
            // Readable after a reboot nobody has attended, so that a television
            // can renew its session without someone in the room.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
    }
}

/// The Keychain refused. The status is Apple's own code, and carries nothing of
/// what was being stored.
nonisolated enum KeychainError: Error, Equatable {
    case unhandled(status: OSStatus)
}
