import Foundation
import Testing
@testable import GroupCloudData

struct TaskAttachmentTests {
    @Test func generatedLinkIDsMatchFirestoreRules() throws {
        var ids = Set<String>()
        for _ in 0..<100 {
            let attachment = TaskAttachment(
                taskID: "task-one", groupID: "group-alpha", uploaderID: "firebase-user",
                title: "成果連結", kind: .externalLink,
                externalURL: "https://example.org/result", status: .ready
            )
            #expect(UUID(uuidString: attachment.id) != nil)
            #expect(attachment.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil)
            #expect(ids.insert(attachment.id).inserted)
            let decoded = try JSONDecoder().decode(TaskAttachment.self, from: JSONEncoder().encode(attachment))
            #expect(decoded.id == attachment.id)
        }
    }

    @Test func existingExplicitIDsAreNotRewritten() {
        let attachment = TaskAttachment(
            id: "ABC-existing-ID", taskID: "task-one", groupID: "group-alpha",
            uploaderID: "firebase-user", title: "成果連結", kind: .externalLink
        )
        #expect(attachment.id == "ABC-existing-ID")
    }
}
