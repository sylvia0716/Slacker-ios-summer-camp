import SwiftUI

/// Central palette for the Oops Bomb visual system.
enum BombTheme {
    static let yellow = Color(red: 1, green: 0.79, blue: 0.05)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    static let secondaryText = Color(red: 0.35, green: 0.34, blue: 0.30)
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.79)
    static let red = Color(red: 196.0 / 255, green: 61.0 / 255, blue: 50.0 / 255) // #C43D32
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
            .compositingGroup()
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

/// 固定在畫面頂端的主題標題列；漸層會保留自己的版面空間，避免遮住內容。
struct BombHeader<Leading: View, Trailing: View>: View {
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets
    @State private var headerHeight: CGFloat = 0

    let title: String
    let subtitle: String?
    let wrapsTitle: Bool
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        wrapsTitle: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.wrapsTitle = wrapsTitle
        self.leading = leading()
        self.trailing = trailing()
    }

    private var fadeHeight: CGFloat {
        max(headerHeight, safeAreaInsets.top) * 0.3
    }

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                leading
                    .frame(minWidth: 44, alignment: .leading)

                Spacer(minLength: 12)

                trailing
                    .frame(minWidth: 44, alignment: .trailing)
            }

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .lineLimit(wrapsTitle ? 2 : 1)
                    .minimumScaleFactor(wrapsTitle ? 1 : 0.65)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BombTheme.ink.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, wrapsTitle ? 60 : 112)
            .allowsHitTesting(false)
        }
        .foregroundStyle(BombTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            headerHeight = height
        }
        .background {
            BombTheme.yellow
                .padding(.top, -safeAreaInsets.top)
                .padding(.leading, -safeAreaInsets.leading)
                .padding(.trailing, -safeAreaInsets.trailing)
        }
        .padding(.bottom, fadeHeight)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [BombTheme.yellow, BombTheme.yellow.opacity(0.82), BombTheme.yellow.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            .allowsHitTesting(false)
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
