import Testing
@testable import GroupCloudData

@Suite @MainActor
struct ProfileNicknameTests {
    @Test func normalizesAndDeduplicatesGroups() async throws {
        var calls: [String] = []
        let repository = ProfileNicknameRepository(client: .init(
            currentUID: { "A" },
            saveAccountName: { calls.append($0) },
            saveMemberName: { group, uid, name in
                #expect(uid == "A")
                #expect(name == "Peach")
                calls.append(group)
            }))
        let result = try await repository.save(" Peach ", groupIDs: ["one", "one", "two"])
        #expect(result == "Peach")
        #expect(calls == ["Peach", "one", "two"])
    }

    @Test func validatesName() throws {
        #expect(throws: NicknameError.invalid) { try ProfileNicknameRepository.normalized("  ") }
        #expect(throws: NicknameError.invalid) { try ProfileNicknameRepository.normalized(String(repeating: "a", count: 61)) }
        #expect(throws: NicknameError.invalid) { try ProfileNicknameRepository.normalized("a\nb") }
    }

    @Test func accountChangeStopsMemberWrites() async {
        var uid = "A"
        var writes = 0
        let repository = ProfileNicknameRepository(client: .init(
            currentUID: { uid }, saveAccountName: { _ in uid = "B" },
            saveMemberName: { _, _, _ in writes += 1 }))
        await #expect(throws: NicknameError.accountChanged) {
            try await repository.save("Peach", groupIDs: ["one"])
        }
        #expect(writes == 0)
    }

    @Test func partialFailureCanRetry() async throws {
        var fail = true
        let repository = ProfileNicknameRepository(client: .init(
            currentUID: { "A" }, saveAccountName: { _ in },
            saveMemberName: { _, _, _ in if fail { throw NicknameError.network } }))
        await #expect(throws: NicknameError.partial) {
            try await repository.save("Peach", groupIDs: ["one"])
        }
        fail = false
        let result = try await repository.save("Peach", groupIDs: ["one"])
        #expect(result == "Peach")
    }
}
