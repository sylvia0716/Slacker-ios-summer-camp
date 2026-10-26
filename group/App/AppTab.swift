import SwiftUI

/// The three top-level destinations in the group-management MVP.
enum AppTab: Hashable, CaseIterable {
    case groups
    case myTasks
    case settings

    var title: String {
        switch self {
        case .groups: L10n.text("群組")
        case .myTasks: L10n.text("我的任務")
        case .settings: L10n.text("設定")
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

struct BombTabBar: View {
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets
    @State private var barHeight: CGFloat = 0

    @Binding var selection: AppTab
    /// 再點一次目前的分頁時呼叫，讓該分頁回到導覽根畫面。
    var onReselect: (AppTab) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: barHeight * 0.75)

            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        if selection == tab {
                            onReselect(tab)
                        } else {
                            selection = tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.symbol)
                                .font(.body.weight(.black))
                                .frame(height: 26)
                            Text(tab.title)
                                .font(.caption2.weight(.black))
                        }
                        .foregroundStyle(selection == tab ? BombTheme.ink : BombTheme.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selection == tab ? BombTheme.yellow : Color.clear)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(5)
            // 分頁列寬度鎖在螢幕的 74%，三個標籤各只分到約 99pt。文字無上限
            // 放大時塞不下就折行，膠囊變高，而上方的間隔是「膠囊高度的 75%」，
            // 於是高度增長被放大 1.75 倍，整條列浮到畫面中間蓋住內容。
            //
            // 封頂只影響分頁列這層外框；系統分頁列同樣會封頂（改以長按放大顯示）。
            // 畫面內容仍完整跟隨系統字級。
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.74 }
            .background(BombTheme.ink)
            .clipShape(.capsule)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                barHeight = height
            }
            .offset(y: safeAreaInsets.bottom * 0.6)
        }
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    BombTheme.yellow.opacity(0),
                    BombTheme.yellow.opacity(0.45),
                    BombTheme.yellow.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.leading, -safeAreaInsets.leading)
            .padding(.trailing, -safeAreaInsets.trailing)
            .padding(.bottom, -safeAreaInsets.bottom)
            .allowsHitTesting(false)
        }
    }
}

struct BombTabBarHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func bombTabBarHidden(_ hidden: Bool = true) -> some View {
        preference(key: BombTabBarHiddenPreferenceKey.self, value: hidden)
    }
}
