import Foundation
import Security

struct PeerCredentialStore: Sendable {
    private let service = "dev.seamless.mac.phone-credentials"

    func credential(for phoneID: String) async throws -> String? {
        try await Task.detached(priority: .userInitiated) { try self.readCredential(for: phoneID) }.value
    }

    func save(_ credential: String, for phoneID: String) async throws {
        try await Task.detached(priority: .userInitiated) { try self.writeCredential(credential, for: phoneID) }.value
    }

    func remove(for phoneID: String) async throws {
        try await Task.detached(priority: .userInitiated) { try self.deleteCredential(for: phoneID) }.value
    }

    private func readCredential(for phoneID: String) throws -> String? {
        var query = baseQuery(phoneID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            throw CredentialError(status: status)
        }
        return text
    }

    private func writeCredential(_ credential: String, for phoneID: String) throws {
        let query = baseQuery(phoneID)
        let data = Data(credential.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertion = SecItemAdd(item as CFDictionary, nil)
            guard insertion == errSecSuccess else { throw CredentialError(status: insertion) }
        } else if status != errSecSuccess {
            throw CredentialError(status: status)
        }
    }

    private func deleteCredential(for phoneID: String) throws {
        let status = SecItemDelete(baseQuery(phoneID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
    }

    private func baseQuery(_ phoneID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: phoneID]
    }
}

private struct CredentialError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Keychain could not access the phone credential (\(status))." }
}
