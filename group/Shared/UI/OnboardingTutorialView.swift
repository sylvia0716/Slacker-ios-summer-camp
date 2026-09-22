import SwiftUI
import UIKit

enum TutorialStep: Equatable {
    case welcome
    case createGroup
    case createGroupForm
    case inviteCode
    case publishTask
    case memberProgress
    case chatEntry
    case aiChat
    case completed
}

enum TutorialTarget: Hashable {
    case createGroupButton
    case inviteCode
    case publishTask
    case memberProgress
    case chatButton
    case chatInput
}

struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TutorialTarget: Anchor<CGRect>],
        nextValue: () -> [TutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget, enabled: Bool = true) -> some View {
        anchorPreference(key: TutorialTargetPreferenceKey.self, value: .bounds) { anchor in
            enabled ? [target: anchor] : [:]
        }
    }

}

struct ToolbarTargetFrameReader: UIViewRepresentable {
    let identifier: String
    let accessibilityLabel: String
    let onChange: (CGRect) -> Void

    func makeUIView(context: Context) -> ToolbarTargetFrameReportingView {
        let view = ToolbarTargetFrameReportingView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.identifier = identifier
        view.targetAccessibilityLabel = accessibilityLabel
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ToolbarTargetFrameReportingView, context: Context) {
        uiView.identifier = identifier
        uiView.targetAccessibilityLabel = accessibilityLabel
        uiView.onChange = onChange
        uiView.beginReporting()
    }
}

final class ToolbarTargetFrameReportingView: UIView {
    var identifier = ""
    var targetAccessibilityLabel = ""
    var onChange: ((CGRect) -> Void)?
    private var lastFrame: CGRect?
    private var retryWorkItem: DispatchWorkItem?
    private var remainingAttempts = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        beginReporting()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        beginReporting()
    }

    func beginReporting() {
        retryWorkItem?.cancel()
        remainingAttempts = 12
        reportTargetFrame()
    }

    private func reportTargetFrame() {
        guard let window else { return }

        if let target = targetView(in: window) {
            let frame = target.convert(target.bounds, to: window)
            guard frame.width > 0, frame.height > 0, frame != lastFrame else { return }
            lastFrame = frame
            DispatchQueue.main.async { [onChange] in
                onChange?(frame)
            }
            return
        }

        guard remainingAttempts > 0 else { return }
        remainingAttempts -= 1
        let workItem = DispatchWorkItem { [weak self] in
            self?.reportTargetFrame()
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func targetView(in window: UIWindow) -> UIView? {
        if let identified = firstDescendant(in: window, matching: {
            $0.accessibilityIdentifier == identifier
        }) {
            return identified
        }

        if let labelled = firstDescendant(in: window, matching: {
            $0.accessibilityLabel == targetAccessibilityLabel && $0 is UIControl
        }) {
            return labelled
        }

        let navigationBars = descendants(in: window)
            .compactMap { $0 as? UINavigationBar }
            .filter { !$0.isHidden && $0.alpha > 0 && $0.window === window }

        return navigationBars
            .flatMap { descendants(in: $0) }
            .compactMap { $0 as? UIControl }
            .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 0 && $0.bounds.height > 0 }
            .max { lhs, rhs in
                lhs.convert(lhs.bounds, to: window).midX < rhs.convert(rhs.bounds, to: window).midX
            }
    }

    private func firstDescendant(
        in root: UIView,
        matching predicate: (UIView) -> Bool
    ) -> UIView? {
        if predicate(root) { return root }
        for subview in root.subviews {
            if let match = firstDescendant(in: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func descendants(in root: UIView) -> [UIView] {
        root.subviews + root.subviews.flatMap { descendants(in: $0) }
    }
}

struct OnboardingTutorialView: View {
    @Binding var step: TutorialStep?
    let targets: [TutorialTarget: CGRect]
    let onFinish: () -> Void
    let onSkip: () -> Void

    var body: some View {
        if let step {
            switch step {
            case .welcome:
                SpotlightOverlay(
                    targetFrame: nil,
                    title: L10n.text("💣 歡迎來到 Oops Bomb"),
                    description: L10n.text("一起建立任務、\n分配工作、\n避免專案爆炸！"),
                    actionTitle: L10n.text("開始拆彈"),
                    action: {
                        self.step = .createGroup
                    },
                    onSkip: onSkip
                )

            case .createGroup:
                SpotlightOverlay(
                    targetFrame: targets[.createGroupButton],
                    title: L10n.text("建立你的第一個專案"),
                    description: L10n.text("點選右上角的「新增」，設定專案名稱與 Deadline。"),
                    actionTitle: nil,
                    action: nil,
                    onSkip: onSkip,
                    cardPlacement: .belowTarget
                )

            case .createGroupForm:
                EmptyView()

            case .inviteCode:
                SpotlightOverlay(
                    targetFrame: targets[.inviteCode],
                    title: L10n.text("🔑 分享這組代碼"),
                    description: L10n.text("邀請隊友加入你的拆彈任務。"),
                    actionTitle: L10n.text("下一步"),
                    action: {
                        self.step = .publishTask
                    },
                    onSkip: onSkip,
                    cardPlacement: .belowTarget
                )

            case .publishTask:
                SpotlightOverlay(
                    targetFrame: targets[.publishTask],
                    title: L10n.text("分配工作給隊友"),
                    description: L10n.text("設定工作內容、負責人與 Deadline。好的分工，是避免爆炸的第一步。"),
                    actionTitle: L10n.text("下一步"),
                    action: {
                        self.step = .memberProgress
                    },
                    onSkip: onSkip
                )

            case .memberProgress:
                SpotlightOverlay(
                    targetFrame: targets[.memberProgress],
                    title: L10n.text("查看每位隊員進度"),
                    description: L10n.text("掌握待完成事項、已完成事項與成果證明。"),
                    actionTitle: L10n.text("前往聊天室"),
                    action: {
                        self.step = .chatEntry
                    },
                    onSkip: onSkip,
                    cardPlacement: .aboveTarget
                )

            case .chatEntry:
                SpotlightOverlay(
                    targetFrame: targets[.chatButton],
                    title: L10n.text("開啟小隊聊天室"),
                    description: L10n.text("點擊聊天室，認識 Bomb AI 協作方式。"),
                    actionTitle: nil,
                    action: nil,
                    onSkip: onSkip
                )

            case .aiChat:
                SpotlightOverlay(
                    targetFrame: targets[.chatInput],
                    title: "🤖 @Bomb AI",
                    description: L10n.text("輸入：@Bomb AI 幫我們整理目前任務\n\nAI 可以協助發想點子、整理討論與提供下一步建議。"),
                    actionTitle: L10n.text("完成訓練"),
                    action: {
                        self.step = .completed
                    },
                    onSkip: onSkip
                )

            case .completed:
                SpotlightOverlay(
                    targetFrame: nil,
                    title: L10n.text("💣 任務準備完成！"),
                    description: L10n.text("你已學會：\n✓ 建立專案\n✓ 分配任務\n✓ 查看進度\n✓ 與 AI 協作"),
                    actionTitle: L10n.text("開始拆彈"),
                    action: onFinish
                )
            }
        }
    }
}

enum SpotlightCardPlacement: Equatable {
    case automatic
    case aboveTarget
    case belowTarget
}

struct SpotlightOverlay: View {
    let targetFrame: CGRect?
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?
    let onSkip: (() -> Void)?
    let cardPlacement: SpotlightCardPlacement

    init(
        targetFrame: CGRect?,
        title: String,
        description: String,
        actionTitle: String?,
        action: (() -> Void)?,
        onSkip: (() -> Void)? = nil,
        cardPlacement: SpotlightCardPlacement = .automatic
    ) {
        self.targetFrame = targetFrame
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
        self.onSkip = onSkip
        self.cardPlacement = cardPlacement
    }

    var body: some View {
        GeometryReader { proxy in
            let localTarget = targetFrame?.insetBy(dx: -8, dy: -8)
            let safeBounds = safeBounds(in: proxy)
            let cardSide = localTarget.map {
                cardPlacement.side(for: $0, in: safeBounds)
            }

            ZStack {
                spotlightMask(size: proxy.size, target: localTarget)
                    .fill(BombTheme.ink.opacity(0.72), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let localTarget, let cardSide {
                    Image(systemName: cardSide == .below ? "arrow.up" : "arrow.down")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(BombTheme.yellow)
                        .position(
                            x: min(max(localTarget.midX, 28), proxy.size.width - 28),
                            y: cardSide == .below ? localTarget.maxY + 25 : localTarget.minY - 25
                        )
                        .allowsHitTesting(false)
                }

                SpotlightCardLayout(
                    target: localTarget,
                    placement: cardPlacement,
                    safeAreaInsets: proxy.safeAreaInsets
                ) {
                    tutorialCard
                }
            }
        }
        .transition(.opacity)
        .zIndex(100)
    }

    private func safeBounds(in proxy: GeometryProxy) -> CGRect {
        CGRect(
            x: proxy.safeAreaInsets.leading,
            y: proxy.safeAreaInsets.top,
            width: proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing,
            height: proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
        )
    }

    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .black))
                .fixedSize(horizontal: false, vertical: true)

            Text(description)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
                    .buttonStyle(.plain)
            } else {
                Text(L10n.text("請點擊聚光燈位置繼續"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }

            if let onSkip {
                Button(L10n.text("跳過教學"), action: onSkip)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BombTheme.ink.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 4))
        .shadow(color: BombTheme.ink, radius: 0, x: 6, y: 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func spotlightMask(size: CGSize, target: CGRect?) -> Path {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: size))
        if let target {
            path.addRoundedRect(in: target, cornerSize: CGSize(width: 16, height: 16))
        }
        return path
    }

}

private enum SpotlightCardSide {
    case above
    case below
}

private extension SpotlightCardPlacement {
    func side(for target: CGRect, in safeBounds: CGRect) -> SpotlightCardSide {
        switch self {
        case .aboveTarget:
            return .above
        case .belowTarget:
            return .below
        case .automatic:
            let spaceAbove = target.minY - safeBounds.minY
            let spaceBelow = safeBounds.maxY - target.maxY
            return spaceBelow >= spaceAbove ? .below : .above
        }
    }
}

private struct SpotlightCardLayout: Layout {
    let target: CGRect?
    let placement: SpotlightCardPlacement
    let safeAreaInsets: EdgeInsets

    private let margin: CGFloat = 16
    private let arrowClearance: CGFloat = 58

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let card = subviews.first else { return }

        let safeBounds = CGRect(
            x: bounds.minX + safeAreaInsets.leading + margin,
            y: bounds.minY + safeAreaInsets.top + margin,
            width: max(0, bounds.width - safeAreaInsets.leading - safeAreaInsets.trailing - margin * 2),
            height: max(0, bounds.height - safeAreaInsets.top - safeAreaInsets.bottom - margin * 2)
        )
        let cardProposal = ProposedViewSize(width: min(350, safeBounds.width), height: nil)
        let measuredSize = card.sizeThatFits(cardProposal)
        let cardSize = CGSize(
            width: min(measuredSize.width, safeBounds.width),
            height: min(measuredSize.height, safeBounds.height)
        )

        let desiredOrigin: CGPoint
        if let target {
            let side = placement.side(for: target, in: safeBounds)
            let y = side == .below
                ? target.maxY + arrowClearance
                : target.minY - arrowClearance - cardSize.height
            desiredOrigin = CGPoint(x: target.midX - cardSize.width / 2, y: y)
        } else {
            desiredOrigin = CGPoint(
                x: safeBounds.midX - cardSize.width / 2,
                y: safeBounds.midY - cardSize.height / 2
            )
        }

        let origin = CGPoint(
            x: min(max(desiredOrigin.x, safeBounds.minX), safeBounds.maxX - cardSize.width),
            y: min(max(desiredOrigin.y, safeBounds.minY), safeBounds.maxY - cardSize.height)
        )
        card.place(
            at: origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: cardSize.width, height: cardSize.height)
        )
    }
}
