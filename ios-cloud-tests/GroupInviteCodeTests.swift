import Testing
@testable import GroupCloudData

struct GroupInviteCodeTests {
    @Test func acceptsCloudAndLegacyCodes() {
        for code in ["ABCD23", "BOMB52", "123456", "team12"] {
            #expect(GroupInviteCode.isValid(code))
        }
        #expect(GroupInviteCode.normalized(" abcd23\n") == "ABCD23")
    }

    @Test func rejectsInvalidScannerPayloads() {
        for code in ["", "ABC", "12345", "1234567", "ABCD2345", "AB-123", String(repeating: "A", count: 33), "１２３４５６", "邀請碼123", "ABCD 2345", "https://example.com/ABCD23"] {
            #expect(!GroupInviteCode.isValid(code))
        }
    }
}
