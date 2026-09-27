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
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { index in
                Rectangle().fill(index.isMultiple(of: 2) ? BombTheme.ink : BombTheme.yellow)
            }
        }
        .frame(height: height)
    }
}

/// A scalable seven-segment digit used for countdown displays.
struct SevenSegmentDigit: View {
    let digit: Character
    let height: CGFloat

    private var activeSegments: Set<Int> {
        switch digit {
        case "0": [0, 1, 2, 4, 5, 6]
        case "1": [2, 5]
        case "2": [0, 2, 3, 4, 6]
        case "3": [0, 2, 3, 5, 6]
        case "4": [1, 2, 3, 5]
        case "5": [0, 1, 3, 5, 6]
        case "6": [0, 1, 3, 4, 5, 6]
        case "7": [0, 2, 5]
        case "8": [0, 1, 2, 3, 4, 5, 6]
        case "9": [0, 1, 2, 3, 5, 6]
        default: []
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentThickness = proxy.size.height * 0.105

            ZStack {
                segment(0, width: width * 0.72, height: segmentThickness)
                    .position(x: width / 2, y: segmentThickness / 2)
                segment(3, width: width * 0.72, height: segmentThickness)
                    .position(x: width / 2, y: proxy.size.height / 2)
                segment(6, width: width * 0.72, height: segmentThickness)
                    .position(x: width / 2, y: proxy.size.height - segmentThickness / 2)

                segment(1, width: segmentThickness, height: proxy.size.height * 0.39, isVertical: true)
                    .position(x: segmentThickness / 2, y: proxy.size.height * 0.26)
                segment(2, width: segmentThickness, height: proxy.size.height * 0.39, isVertical: true)
                    .position(x: width - segmentThickness / 2, y: proxy.size.height * 0.26)
                segment(4, width: segmentThickness, height: proxy.size.height * 0.39, isVertical: true)
                    .position(x: segmentThickness / 2, y: proxy.size.height * 0.74)
                segment(5, width: segmentThickness, height: proxy.size.height * 0.39, isVertical: true)
                    .position(x: width - segmentThickness / 2, y: proxy.size.height * 0.74)
            }
        }
        .frame(width: height * 0.56, height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ index: Int, width: CGFloat, height: CGFloat, isVertical: Bool = false) -> some View {
        SevenSegmentBar(isVertical: isVertical)
            .fill(.white)
            .frame(width: width, height: height)
            .opacity(activeSegments.contains(index) ? 1 : 0)
    }
}

private struct SevenSegmentBar: Shape {
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if isVertical {
            let inset = rect.width / 2
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inset))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        } else {
            let inset = rect.height / 2
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

/// 固定在畫面頂端的主題標題列；漸層會保留自己的版面空間，避免遮住內容。
struct BombHeader<Leading: View, Trailing: View>: View {
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets
    @State private var headerHeight: CGFloat = 0
    @State private var leadingWidth: CGFloat = 44
    @State private var trailingWidth: CGFloat = 44

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
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leadingWidth = $0 }

                Spacer(minLength: 12)

                trailing
                    .frame(minWidth: 44, alignment: .trailing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailingWidth = $0 }
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
            .padding(.horizontal, max(leadingWidth, trailingWidth) + 12)
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
            .frame(width: 44, height: 44)
            .background(BombTheme.ink)
            .clipShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
