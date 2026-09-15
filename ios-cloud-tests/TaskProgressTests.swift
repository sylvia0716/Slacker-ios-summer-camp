import Foundation
import Testing
@testable import GroupCloudData

struct TaskProgressTests {
    func task() -> ProjectTask {
        ProjectTask(id: UUID(), groupID: UUID(), title: "工作", detail: "", weight: 1,
                    ownerMemberID: UUID(), subtasks: [], deliverable: nil,
                    firestoreDocumentID: UUID().uuidString.lowercased())
    }
    func result() -> Deliverable {
        Deliverable(id: UUID(), title: "成果", url: nil, submittedAt: .now, isApproved: false)
    }
    @Test func uploadAloneIsNotCompleted() {
        var t = task()
        t.deliverable = result()
        t.status = .submitted
        #expect(t.progress == 0)
        #expect(!t.isCompleted)
        t.status = .completed
        #expect(t.progress == 100)
        #expect(t.isCompleted)
        t.deliverable = nil
        #expect(t.progress == 0)
    }
    @Test func subtaskProgressAndApprovalAreSeparate() {
        var t = task()
        t.subtasks = [Subtask(id: UUID(), title: "A", isComplete: true, weight: 1),
                      Subtask(id: UUID(), title: "B", isComplete: false, weight: 1)]
        t.deliverable = result()
        t.status = .submitted
        #expect(t.progress == 50)
        t.subtasks[1].isComplete = true
        #expect(t.progress == 100)
        #expect(!t.isCompleted)
        t.status = .completed
        #expect(t.isCompleted)
    }
    @Test func cloudApprovalFieldsDecode() throws {
        let data = Data(#"{"title":"工作","status":"completed","confirmedAttachmentID":"result-id","confirmedMemberUIDs":["A","B"]}"#.utf8)
        let decoded = try JSONDecoder().decode(CloudTaskDocument.self, from: data)
        #expect(decoded.status == .completed)
        #expect(decoded.confirmedMemberUIDs == ["A", "B"])
        #expect(decoded.confirmedAttachmentID == "result-id")
    }
}
