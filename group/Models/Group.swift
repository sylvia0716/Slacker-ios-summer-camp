import Foundation

/// A future collaboration space. Store group-specific metadata here, not in a view.
struct Group: Identifiable, Hashable {
    let id: UUID
    var name: String
    var code: String
    var deadline: Date
    var memberIDs: [UUID]
    var taskIDs: [UUID]
}
