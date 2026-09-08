import SwiftUI

/// The three top-level destinations in the group-management MVP.
enum AppTab: Hashable, CaseIterable {
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

struct BombTabBar: View {
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets
    @State private var barHeight: CGFloat = 0

    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: barHeight * 0.75)

            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.symbol)
                                .font(.body.weight(.black))
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
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.74 }
            .background(BombTheme.ink)
            .clipShape(.capsule)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                barHeight = height
            }
            .padding(.bottom, barHeight * 0.12)
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
