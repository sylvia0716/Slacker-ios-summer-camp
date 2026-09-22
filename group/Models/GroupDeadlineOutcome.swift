import Foundation

/// 群組截止後的單一狀態來源。
enum GroupDeadlineOutcome: Equatable {
    case active
    case completed
    case incomplete

    static func resolve(
        deadline: Date,
        settledAt: Date? = nil,
        progress: Int,
        now: Date = .now
    ) -> Self {
        if settledAt != nil { return .completed }
        guard now >= deadline else { return .active }
        return progress >= 100 ? .completed : .incomplete
    }
}
