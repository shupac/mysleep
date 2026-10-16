import Foundation
import Security

protocol SessionStorage {
    func load() throws -> SavedSession?
    func save(_ session: SavedSession) throws
    func clear() throws
}
struct KeychainSessionStorage: SessionStorage {
    // App Intents run in the app process; no shared groups or extensions needed.
    private let service = "personal.eightsleep.native"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "account"]
    }
    func load() throws -> SavedSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let saved = try? JSONDecoder().decode(SavedSession.self, from: data) else { throw SleepError.secureStorage }
        _ = try Credentials(email: saved.credentials.email, password: saved.credentials.password, timezone: saved.credentials.timezone)
        return saved
    }
    func save(_ session: SavedSession) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SleepError.secureStorage }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SleepError.secureStorage }
    }
}
