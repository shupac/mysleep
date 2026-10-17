import XCTest
import Security
@testable import SleepCore

private final class SyntheticKeychain {
    var item: [String: Any]?
    var readStatus: OSStatus = errSecSuccess
    var updateStatus: OSStatus = errSecSuccess
    var updates: [[String: Any]] = []
    var additions: [[String: Any]] = []
    var operations: KeychainOperations {
        KeychainOperations(
            copyMatching: { _ in
                if self.readStatus != errSecSuccess { return (self.readStatus, nil) }
                return (self.item == nil ? errSecItemNotFound : errSecSuccess, self.item)
            },
            update: { _, attributes in
                self.updates.append(attributes)
                if self.updateStatus != errSecSuccess { return self.updateStatus }
                guard let item = self.item else { return errSecItemNotFound }
                self.item = item.merging(attributes) { _, new in new }
                return errSecSuccess
            },
            add: { attributes in self.additions.append(attributes); self.item = attributes; return errSecSuccess },
            delete: { _ in self.item = nil; return errSecSuccess }
        )
    }
}

final class KeychainTests: XCTestCase {
    private func savedSession() throws -> SavedSession {
        SavedSession(credentials: try credentials(), token: AccessToken(value: "synthetic-token", expiresAt: testNow, userID: "uid"))
    }
    private func populate(_ keychain: SyntheticKeychain, accessibility: CFString) throws -> Data {
        let data = try JSONEncoder().encode(savedSession())
        keychain.item = [kSecValueData as String: data, kSecAttrAccessible as String: accessibility]
        return data
    }
    func testExistingUnlockedSessionMigratesInPlaceWithoutChangingCredentials() throws {
        let keychain = SyntheticKeychain()
        let original = try populate(keychain, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        let storage = KeychainSessionStorage(operations: keychain.operations)
        let saved = try storage.load()
        XCTAssertEqual(saved?.credentials, try credentials())
        XCTAssertEqual(saved?.token?.value, "synthetic-token")
        XCTAssertEqual(keychain.updates.count, 1)
        XCTAssertEqual(keychain.item?[kSecValueData as String] as? Data, original)
        XCTAssertEqual(keychain.item?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(keychain.item?[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertTrue(keychain.additions.isEmpty)
        _ = try storage.load()
        XCTAssertEqual(keychain.updates.count, 1)
    }
    func testMigratedSessionReadsWithoutAWriteWhenLocked() throws {
        let keychain = SyntheticKeychain()
        _ = try populate(keychain, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        keychain.updateStatus = errSecInteractionNotAllowed
        let saved = try KeychainSessionStorage(operations: keychain.operations).load()
        XCTAssertNotNil(saved)
        XCTAssertTrue(keychain.updates.isEmpty)
    }
    func testFailedMigrationPreservesOldSessionAndSurfacesError() throws {
        let keychain = SyntheticKeychain()
        let original = try populate(keychain, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        keychain.updateStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try KeychainSessionStorage(operations: keychain.operations).load()) {
            XCTAssertEqual($0 as? SleepError, .secureStorage)
        }
        XCTAssertEqual(keychain.item?[kSecValueData as String] as? Data, original)
        XCTAssertEqual(keychain.item?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertTrue(keychain.additions.isEmpty)
    }
    func testNewAndRenewedSessionsUseDeviceOnlyBackgroundAccess() throws {
        let keychain = SyntheticKeychain()
        let storage = KeychainSessionStorage(operations: keychain.operations)
        try storage.save(savedSession())
        XCTAssertEqual(keychain.additions.count, 1)
        XCTAssertEqual(keychain.item?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(keychain.item?[kSecAttrSynchronizable as String] as? Bool, false)
        var renewed = try savedSession()
        renewed.token = AccessToken(value: "renewed-token", expiresAt: testNow.addingTimeInterval(3600), userID: "uid")
        try storage.save(renewed)
        XCTAssertEqual(try storage.load()?.token?.value, "renewed-token")
        XCTAssertEqual(keychain.additions.count, 1)
        XCTAssertEqual(keychain.updates.last?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
    func testBeforeFirstUnlockFailureDoesNotMigrateOrDeleteSession() throws {
        let keychain = SyntheticKeychain()
        let original = try populate(keychain, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        keychain.readStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try KeychainSessionStorage(operations: keychain.operations).load()) {
            XCTAssertEqual($0 as? SleepError, .secureStorage)
        }
        XCTAssertEqual(keychain.item?[kSecValueData as String] as? Data, original)
        XCTAssertTrue(keychain.updates.isEmpty)
    }
}
