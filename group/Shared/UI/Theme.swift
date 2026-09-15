import SwiftUI

/// Central palette for the Group Bomb visual system.
enum BombTheme {
    static let yellow = Color(red: 1, green: 0.79, blue: 0.05)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.79)
    static let red = Color(red: 0.86, green: 0.17, blue: 0.12)
    static let green = Color(red: 0.16, green: 0.55, blue: 0.32)
}

private struct BombSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var bombSafeAreaInsets: EdgeInsets {
        get { self[BombSafeAreaInsetsKey.self] }
        set { self[BombSafeAreaInsetsKey.self] = newValue }
    }
}

/// Shared comic-style card treatment. Keep feature-specific layout out of this file.
struct ComicCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, lineWidth: 3))
            .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
    }
}

extension View {
    func comicCard() -> some View { modifier(ComicCard()) }
}

/// Reusable warning-stripe decoration for deadline and status surfaces.
struct HazardStripe: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { index in
                Rectangle().fill(index.isMultiple(of: 2) ? BombTheme.yellow : BombTheme.ink)
            }
        }.frame(height: 10)
    }
}

/// 固定在畫面頂端的主題標題列。
struct BombHeader<Leading: View, Trailing: View>: View {
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets

    let title: String
    let subtitle: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
                .frame(minWidth: 44, alignment: .leading)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BombTheme.ink.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            trailing
                .frame(minWidth: 44, alignment: .trailing)
        }
        .foregroundStyle(BombTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            BombTheme.yellow
                .padding(.top, -safeAreaInsets.top)
                .padding(.leading, -safeAreaInsets.leading)
                .padding(.trailing, -safeAreaInsets.trailing)
        }
        .zIndex(50)
    }
}

struct BombHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(BombTheme.yellow)
            .frame(width: 42, height: 42)
            .background(BombTheme.ink)
            .clipShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
