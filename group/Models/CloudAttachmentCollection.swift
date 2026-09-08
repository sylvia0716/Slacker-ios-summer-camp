import Foundation

/// Each listener event replaces the complete collection, including an empty collection.
struct CloudAttachmentCollection {
    let attachments: [TaskAttachment]
    var latestDeliverable: Deliverable? {
        attachments.first(where: { $0.status == .ready }).map { Deliverable(attachment: $0) }
    }

    init(_ attachments: [TaskAttachment], groupID: String, taskID: String) throws {
        guard Set(attachments.map(\.id)).count == attachments.count,
              attachments.allSatisfy({ $0.groupID == groupID && $0.taskID == taskID && UUID(uuidString: $0.id) != nil }) else {
            throw GroupLoadError.invalidData
        }
        self.attachments = attachments.sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }
}
