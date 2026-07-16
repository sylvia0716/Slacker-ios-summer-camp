import Foundation

/// The smallest unit that can be marked complete and contribute to task progress.
struct Subtask: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isComplete: Bool
    var weight: Int
}
