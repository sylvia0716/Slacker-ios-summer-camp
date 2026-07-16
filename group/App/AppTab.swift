/// The three top-level destinations in the group-management MVP.
enum AppTab: Hashable {
    case groups
    case myTasks
    case settings

    var title: String {
        switch self {
        case .groups: "群組"
        case .myTasks: "我的任務"
        case .settings: "設定"
        }
    }

    var symbol: String {
        switch self {
        case .groups: "person.3.fill"
        case .myTasks: "checklist"
        case .settings: "gearshape.fill"
        }
    }
}
