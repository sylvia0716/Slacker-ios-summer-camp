import SwiftUI

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
    static var defaultValue: [TutorialTarget: CGRect] = [:]

    static func reduce(value: inout [TutorialTarget: CGRect], nextValue: () -> [TutorialTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget, enabled: Bool = true) -> some View {
        background {
            if enabled {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialTargetPreferenceKey.self,
                        value: [target: proxy.frame(in: .global)]
                    )
                }
            }
        }
    }
}

struct OnboardingTutorialView: View {
    @Binding var step: TutorialStep?
    let targets: [TutorialTarget: CGRect]
    let onFinish: () -> Void

    var body: some View {
        if let step {
            switch step {
            case .welcome:
                SpotlightOverlay(
                    targetFrame: nil,
                    title: "💣 歡迎來到 Group Bomb",
                    description: "一起建立任務、\n分配工作、\n避免專案爆炸！",
                    actionTitle: "開始拆彈"
                ) {
                    self.step = .createGroup
                }

            case .createGroup:
                SpotlightOverlay(
                    targetFrame: targets[.createGroupButton],
                    title: "建立你的第一個專案",
                    description: "點擊 ＋，設定專案名稱與 Deadline。",
                    actionTitle: nil,
                    action: nil
                )

            case .createGroupForm:
                EmptyView()

            case .inviteCode:
                SpotlightOverlay(
                    targetFrame: targets[.inviteCode],
                    title: "🔑 分享這組代碼",
                    description: "邀請隊友加入你的拆彈任務。",
                    actionTitle: "下一步"
                ) {
                    self.step = .publishTask
                }

            case .publishTask:
                SpotlightOverlay(
                    targetFrame: targets[.publishTask],
                    title: "分配工作給隊友",
                    description: "設定工作內容、負責人與 Deadline。好的分工，是避免爆炸的第一步。",
                    actionTitle: "下一步"
                ) {
                    self.step = .memberProgress
                }

            case .memberProgress:
                SpotlightOverlay(
                    targetFrame: targets[.memberProgress],
                    title: "查看每位隊員進度",
                    description: "掌握待完成事項、已完成事項與成果證明。",
                    actionTitle: "前往聊天室"
                ) {
                    self.step = .chatEntry
                }

            case .chatEntry:
                SpotlightOverlay(
                    targetFrame: targets[.chatButton],
                    title: "開啟小隊聊天室",
                    description: "點擊聊天室，認識 Bomb AI 協作方式。",
                    actionTitle: nil,
                    action: nil
                )

            case .aiChat:
                SpotlightOverlay(
                    targetFrame: targets[.chatInput],
                    title: "🤖 @Bomb AI",
                    description: "輸入：@Bomb AI 幫我們整理目前任務\n\nAI 可以協助發想點子、整理討論與提供下一步建議。",
                    actionTitle: "完成訓練"
                ) {
                    self.step = .completed
                }

            case .completed:
                SpotlightOverlay(
                    targetFrame: nil,
                    title: "💣 任務準備完成！",
                    description: "你已學會：\n✓ 建立專案\n✓ 分配任務\n✓ 查看進度\n✓ 與 AI 協作",
                    actionTitle: "開始拆彈",
                    action: onFinish
                )
            }
        }
    }
}

struct SpotlightOverlay: View {
    let targetFrame: CGRect?
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let rootFrame = proxy.frame(in: .global)
            let localTarget = targetFrame.map {
                CGRect(
                    x: $0.minX - rootFrame.minX,
                    y: $0.minY - rootFrame.minY,
                    width: $0.width,
                    height: $0.height
                ).insetBy(dx: -8, dy: -8)
            }
            let targetIsHigh = (localTarget?.midY ?? proxy.size.height / 2) < proxy.size.height / 2

            ZStack {
                spotlightMask(size: proxy.size, target: localTarget)
                    .fill(BombTheme.ink.opacity(0.72), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let localTarget {
                    Image(systemName: targetIsHigh ? "arrow.up" : "arrow.down")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(BombTheme.yellow)
                        .position(
                            x: min(max(localTarget.midX, 28), proxy.size.width - 28),
                            y: targetIsHigh ? localTarget.maxY + 25 : localTarget.minY - 25
                        )
                        .allowsHitTesting(false)
                }

                tutorialCard
                    .frame(maxWidth: min(350, proxy.size.width - 32))
                    .position(
                        x: proxy.size.width / 2,
                        y: cardCenterY(in: proxy.size, target: localTarget, targetIsHigh: targetIsHigh)
                    )
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(100)
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
                Text("請點擊聚光燈位置繼續")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }
        }
        .padding(18)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 4))
        .shadow(color: BombTheme.ink, radius: 0, x: 6, y: 6)
        .padding(.horizontal, 16)
    }

    private func spotlightMask(size: CGSize, target: CGRect?) -> Path {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: size))
        if let target {
            path.addRoundedRect(in: target, cornerSize: CGSize(width: 16, height: 16))
        }
        return path
    }

    private func cardCenterY(in size: CGSize, target: CGRect?, targetIsHigh: Bool) -> CGFloat {
        guard let target else { return size.height / 2 }
        if targetIsHigh {
            return min(size.height - 145, target.maxY + 155)
        }
        return max(145, target.minY - 155)
    }
}
