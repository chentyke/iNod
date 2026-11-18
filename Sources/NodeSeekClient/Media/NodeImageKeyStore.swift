import Foundation
import os
import Security

public enum NodeImageKeyStore {
    private static let service = "NodeSeek.NodeImage.APIKey"

    #if DEBUG
    private static let uiTestStorage = OSAllocatedUnfairLock<[Int: String]?>(initialState: nil)

    static func configureForUITests(userID: Int?, key: String?) {
        let initial: [Int: String] = if let userID, let key, !key.isEmpty {
            [userID: key]
        } else {
            [:]
        }
        uiTestStorage.withLock { $0 = initial }
    }
    #endif

    public static func read(userID: Int) throws -> String {
        #if DEBUG
        if let override = uiTestStorage.withLock({ $0?[userID] ?? ($0 != nil ? "" : nil) }) {
            return override
        }
        #endif
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
        #if DEBUG
        let handled = uiTestStorage.withLock { storage -> Bool in
            guard storage != nil else { return false }
            if key.isEmpty { storage?.removeValue(forKey: userID) }
            else { storage?[userID] = key }
            return true
        }
        if handled { return }
        #endif
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
