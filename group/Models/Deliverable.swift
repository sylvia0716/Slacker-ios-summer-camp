import Foundation

/// Metadata for a submitted outcome. MVP uses a mock file name or link instead of real upload storage.
struct Deliverable: Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: URL?
    var submittedAt: Date
    var isApproved: Bool
}
