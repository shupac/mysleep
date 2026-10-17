import Foundation
import Security

protocol SessionStorage {
    func load() throws -> SavedSession?
    func save(_ session: SavedSession) throws
    func clear() throws
}
/// Injectable Security operations let migration tests use synthetic items only.
struct KeychainOperations {
    var copyMatching: ([String: Any]) -> (OSStatus, [String: Any]?)
    var update: ([String: Any], [String: Any]) -> OSStatus
    var add: ([String: Any]) -> OSStatus
    var delete: ([String: Any]) -> OSStatus

    static let system = KeychainOperations(
        copyMatching: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? [String: Any])
        },
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        add: { SecItemAdd($0 as CFDictionary, nil) },
        delete: { SecItemDelete($0 as CFDictionary) }
    )
}

struct KeychainSessionStorage: SessionStorage {
    // App Intents run in the app process; no shared groups or extensions needed.
    private let service = "personal.eightsleep.native"
    private let operations: KeychainOperations
    init(operations: KeychainOperations = .system) { self.operations = operations }
    private var backgroundAttributes: [String: Any] {
        [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
         kSecAttrSynchronizable as String: false]
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "account"]
    }
    func load() throws -> SavedSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, item) = operations.copyMatching(request)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item, let data = item[kSecValueData as String] as? Data,
              let saved = try? JSONDecoder().decode(SavedSession.self, from: data) else { throw SleepError.secureStorage }
        _ = try Credentials(email: saved.credentials.email, password: saved.credentials.password, timezone: saved.credentials.timezone)
        // Migrate the existing item in place after the next unlocked app launch.
        // Already-migrated reads must not issue a Keychain write while locked.
        if item[kSecAttrAccessible as String] as? String != kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String {
            guard operations.update(query, backgroundAttributes) == errSecSuccess else { throw SleepError.secureStorage }
        }
        return saved
    }
    func save(_ session: SavedSession) throws {
        var attributes = backgroundAttributes
        attributes[kSecValueData as String] = try JSONEncoder().encode(session)
        var status = operations.update(query, attributes)
        if status == errSecItemNotFound {
            status = operations.add(query.merging(attributes) { _, new in new })
        }
        guard status == errSecSuccess else { throw SleepError.secureStorage }
    }
    func clear() throws {
        let status = operations.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SleepError.secureStorage }
    }
}
