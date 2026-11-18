import Foundation

public struct PasswordValidation: Equatable, Sendable {
    public static let lengthRange = 6...18

    public let currentPassword: String
    public let newPassword: String
    public let confirmation: String

    public init(currentPassword: String, newPassword: String, confirmation: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
        self.confirmation = confirmation
    }

    public static func containsOnlyAllowedCharacters(_ text: String) -> Bool {
        text.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)     // 0-9
                || (byte >= 65 && byte <= 90)  // A-Z
                || (byte >= 97 && byte <= 122) // a-z
                || byte == 46                  // .
                || byte == 45                  // -
                || byte == 95                  // _
        }
    }

    public var hasAllowedCharacters: Bool {
        Self.containsOnlyAllowedCharacters(newPassword)
    }

    public var isLengthValid: Bool {
        Self.lengthRange.contains(newPassword.count)
    }

    public var isUnchanged: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && currentPassword == newPassword
    }

    public var matchesConfirmation: Bool {
        !confirmation.isEmpty && newPassword == confirmation
    }

    public var canSubmit: Bool {
        !currentPassword.isEmpty
            && !newPassword.isEmpty
            && hasAllowedCharacters
            && isLengthValid
            && !isUnchanged
            && matchesConfirmation
    }

    /// Returns a specific, localized reason when the user has typed invalid or mismatched input,
    /// or `nil` when fields are still incomplete without a rule violation.
    public var issueMessage: String? {
        if !newPassword.isEmpty {
            if !hasAllowedCharacters {
                return "新密码包含不支持的字符，仅可使用英文字母、数字及 . - _。"
            }
            if !isLengthValid {
                return "新密码长度需为 6–18 位（当前 \(newPassword.count) 位）。"
            }
            if isUnchanged {
                return "新密码不能与当前密码相同。"
            }
        }
        if !confirmation.isEmpty && newPassword != confirmation {
            return "两次输入的新密码不一致。"
        }
        return nil
    }
}
