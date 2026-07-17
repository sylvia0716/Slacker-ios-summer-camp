import Foundation

/// 群組截止後的單一狀態來源。
enum GroupDeadlineOutcome: Equatable {
    case active
    case completed
    case incomplete

    static func resolve(deadline: Date, progress: Int, now: Date = .now) -> Self {
        guard now >= deadline else { return .active }
        return progress >= 100 ? .completed : .incomplete
    }
}
