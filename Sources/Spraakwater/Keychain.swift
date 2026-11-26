import Foundation
import Security

enum Keychain {
    private static let service = "nl.avido.spraakwater"
    /// Service name from when the app was still called Dicteer, so existing keys carry over.
    private static let legacyService = "nl.avido.dicteer"

    private static func query(_ account: String, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(account: String) -> String {
        let value = read(account: account, service: service)
        if !value.isEmpty { return value }
        let legacy = read(account: account, service: legacyService)
        if !legacy.isEmpty { write(legacy, account: account) }
        return legacy
    }

    private static func read(account: String, service: String) -> String {
        var query = query(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    /// Stores the value, or removes the item when the value is empty.
    static func write(_ value: String, account: String) {
        let base = query(account)
        if value.isEmpty {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
