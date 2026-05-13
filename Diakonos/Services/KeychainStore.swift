import Foundation
import Security

/// Minimal Keychain wrapper for storing API keys (Anthropic, OpenAI, Hermes, …).
enum KeychainStore {
    static let service = "com.uberkiwi.diakonos"

    enum Key: String, CaseIterable {
        case anthropic   = "api.anthropic"
        case openai      = "api.openai"
        case hermes      = "api.hermes"
        case googleAI    = "api.googleAI"
    }

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ key: Key, value: String) -> Bool {
        let data = value.data(using: .utf8) ?? Data()

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
