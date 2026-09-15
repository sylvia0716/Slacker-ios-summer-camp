import Testing
@testable import GroupCloudData

struct GroupInviteCodeTests {
    @Test func generatedCodesHaveSixAlphanumericCharacters() {
        for _ in 0..<1000 {
            let code = GroupInviteCode.generate()
            #expect(code.count == 6)
            #expect(GroupInviteCode.isValid(code))
        }
    }
    @Test func rejectsWrongLengthOrCharacters() {
        for code in ["", "ABCDE", "ABCDEFG", "AB-CD1", "abc123", "中文1234", "ABC12 "] {
            #expect(!GroupInviteCode.isValid(code))
        }
        #expect(GroupInviteCode.isValid("ABC123"))
    }
}
