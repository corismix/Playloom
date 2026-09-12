import Foundation
import Security

nonisolated protocol APIKeyStoring: Sendable {
    func read() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

nonisolated final class APIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String = "io.github.corismix.playloom.credentials", account: String) { self.service = service; self.account = account }

    func read() throws -> String? {
        var query = baseQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeyStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KeyStoreError.empty }
        let data = Data(key.utf8); let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil); guard addStatus == errSecSuccess else { throw KeyStoreError.status(addStatus) }
        } else if status != errSecSuccess { throw KeyStoreError.status(status) }
    }

    func delete() throws { let status = SecItemDelete(baseQuery as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreError.status(status) } }
    private var baseQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
}
nonisolated enum KeyStoreError: Error { case empty, status(OSStatus) }
