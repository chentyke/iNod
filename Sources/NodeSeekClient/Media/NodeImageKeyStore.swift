import Foundation
import Security

public enum NodeImageKeyStore {
    private static let service = "NodeSeek.NodeImage.APIKey"
    public static func read(userID: Int) throws -> String {
        var query = query(userID: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data, let key = String(data: data, encoding: .utf8) else { throw SiteError.message("无法读取图床密钥，请重试。") }
        return key
    }

    public static func save(_ key: String, userID: Int) throws {
        let query = query(userID: userID)
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SiteError.message("无法移除图床密钥。") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(attributes) { _, new in new }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw SiteError.message("无法保存图床密钥。") }
        } else if status != errSecSuccess { throw SiteError.message("无法保存图床密钥。") }
    }

    private static func query(userID: Int) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: String(userID)]
    }
}
