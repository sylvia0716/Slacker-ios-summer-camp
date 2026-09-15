import Testing
@testable import GroupCloudData

struct GroupInviteCodeTests {
    @Test func acceptsCloudAndLegacyCodes() {
        for code in ["ABCD2345", "BOMB52", "TEST", "team-123", String(repeating: "A", count: 32)] {
            #expect(GroupInviteCode.isValid(code))
        }
        #expect(GroupInviteCode.normalized(" abcd2345\n") == "ABCD2345")
    }

    @Test func rejectsInvalidScannerPayloads() {
        for code in ["", "ABC", String(repeating: "A", count: 33), "１２３４５６", "邀請碼123", "ABCD 2345", "https://example.com/ABCD2345"] {
            #expect(!GroupInviteCode.isValid(code))
        }
    }
}
