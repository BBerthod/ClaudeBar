import Foundation
import Security

protocol CredentialStore {
    func readRaw(service: String) -> Data?
    func writeRaw(_ data: Data, service: String) throws
    func discoverService() -> String?
}

final class KeychainCredentialStore: CredentialStore {
    private var itemReferences: [String: Data] = [:]

    func readRaw(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        itemReferences[service] = nil
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let reference = item[kSecValuePersistentRef as String] as? Data else { return nil }
        itemReferences[service] = reference
        return data
    }

    func writeRaw(_ data: Data, service: String) throws {
        // Target the exact item read, even if several accounts share a service.
        // Update only the payload: account, ACL and all other attributes survive.
        guard let reference = itemReferences[service] else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecItemNotFound))
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValuePersistentRef as String: reference
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func discoverService() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return nil }
        return items.compactMap { $0[kSecAttrService as String] as? String }
            .first { $0.hasPrefix("Claude Code-credentials-") }
    }
}
