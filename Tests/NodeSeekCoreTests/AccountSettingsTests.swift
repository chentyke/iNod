import Foundation
import Testing
@testable import NodeSeekCore

struct AccountSettingsTests {
    @Test func passwordValidationAcceptsValidInputAndExplainsViolations() {
        let empty = PasswordValidation(currentPassword: "", newPassword: "", confirmation: "")
        #expect(!empty.canSubmit)
        #expect(empty.issueMessage == nil)

        let invalidChars = PasswordValidation(currentPassword: "old_pass1", newPassword: "bad@pass!", confirmation: "")
        #expect(!invalidChars.hasAllowedCharacters)
        #expect(!invalidChars.canSubmit)
        #expect(invalidChars.issueMessage?.contains("不支持的字符") == true)

        let tooShort = PasswordValidation(currentPassword: "old_pass1", newPassword: "abc12", confirmation: "abc12")
        #expect(!tooShort.isLengthValid)
        #expect(!tooShort.canSubmit)
        #expect(tooShort.issueMessage?.contains("6–18 位") == true)

        let tooLong = PasswordValidation(
            currentPassword: "old_pass1",
            newPassword: String(repeating: "a", count: 19),
            confirmation: String(repeating: "a", count: 19)
        )
        #expect(!tooLong.isLengthValid)
        #expect(!tooLong.canSubmit)

        let unchanged = PasswordValidation(currentPassword: "same_pass1", newPassword: "same_pass1", confirmation: "same_pass1")
        #expect(unchanged.isUnchanged)
        #expect(!unchanged.canSubmit)
        #expect(unchanged.issueMessage?.contains("相同") == true)

        let incompleteConfirmation = PasswordValidation(currentPassword: "old_pass1", newPassword: "new.pass-1_A", confirmation: "")
        #expect(!incompleteConfirmation.canSubmit)
        #expect(incompleteConfirmation.issueMessage == nil)

        let mismatched = PasswordValidation(currentPassword: "old_pass1", newPassword: "new.pass-1_A", confirmation: "new.pass-2_B")
        #expect(!mismatched.matchesConfirmation)
        #expect(!mismatched.canSubmit)
        #expect(mismatched.issueMessage?.contains("不一致") == true)

        let valid = PasswordValidation(currentPassword: "old_pass1", newPassword: "new.pass-1_A", confirmation: "new.pass-1_A")
        #expect(valid.canSubmit)
        #expect(valid.issueMessage == nil)
    }

    @Test func homepageCategoryMapsKnownForumSymbolsAndFallsBackCleanly() {
        #expect(HomepageCategory(id: "tech", title: "技术", enabled: true).symbol == "chevron.left.forwardslash.chevron.right")
        #expect(HomepageCategory(id: "daily", title: "日常", enabled: true).symbol == "cup.and.saucer")
        #expect(HomepageCategory(id: "trade", title: "交易", enabled: false).symbol == "arrow.left.arrow.right")
        #expect(HomepageCategory(id: "custom-board", title: "新板块", enabled: true).symbol == "bubble.left.and.bubble.right")
    }

    @Test func blockedMemberNormalizesUsernameAndBuildsAvatarURL() {
        #expect(BlockedMember.normalizedUsername("  alice  ") == "alice")
        #expect(BlockedMember.normalizedUsername(" @bob_42 ") == "bob_42")
        #expect(BlockedMember.normalizedUsername("   ") == nil)
        #expect(BlockedMember.normalizedUsername("@   ") == nil)

        let member = BlockedMember(id: 9_900_088, name: "spammer")
        #expect(member.avatarURL.absoluteString == "https://www.nodeseek.com/avatar/9900088.png")
    }

    @Test func accountSecurityAndOTPModelsDecodeWebsitePayloads() throws {
        let decoder = JSONDecoder()
        let security = try decoder.decode(
            AccountSecurity.self,
            from: Data(#"{"twoFactorEnabled":true,"history":[{"id":"0-1700000000","ip":"203.0.113.42","createdAt":"2026-11-18T01:20:00.000Z"}]}"#.utf8)
        )
        #expect(security.twoFactorEnabled)
        #expect(security.history.count == 1)
        #expect(security.history.first?.ip == "203.0.113.42")

        let setup = try decoder.decode(
            OTPSetup.self,
            from: Data(#"{"secret":"JBSWY3DPEHPK3PXP","uri":"otpauth://totp/NodeSeek:tester?secret=JBSWY3DPEHPK3PXP"}"#.utf8)
        )
        #expect(setup.secret == "JBSWY3DPEHPK3PXP")
        #expect(setup.uri.hasPrefix("otpauth://totp/"))
    }
}
