import SwiftUI

/// Display-only data used by the Phase 1 group-detail prototype.
/// It intentionally stays separate from the app's unfinished collaboration models.
struct MemberProgressPreviewItem: Identifiable {
    let id: String
    let name: String
    let role: String
    let progress: Int
    let currentTask: String
    let status: String
    let showsNudge: Bool
}

/// Static member summary for the Phase 1 group-detail screen.
struct MemberProgressCard: View {
    let member: MemberProgressPreviewItem
    let onPoke: (PokeStyle) -> Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.system(.headline, design: .rounded, weight: .black))
                    Text(member.role)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(member.progress)%")
                    .font(.system(.title3, design: .rounded, weight: .black))

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .accessibilityLabel("展開成員任務")
            }

            ProgressView(value: Double(member.progress), total: 100)
                .tint(progressColor)
                .scaleEffect(y: 1.5)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "scope")
                    .font(.caption.weight(.bold))
                Text(member.currentTask)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Text(member.status)
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(member.showsNudge ? BombTheme.red : BombTheme.yellow)
                    .foregroundStyle(member.showsNudge ? Color.white : BombTheme.ink)
                    .clipShape(.capsule)

                Spacer()

                if member.showsNudge {
                    PokeActionButton(onPoke: onPoke)
                }
            }
        }
        .comicCard()
        .accessibilityElement(children: .contain)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(BombTheme.ink)
            Text(String(member.name.prefix(1)).uppercased())
                .font(.title3.weight(.black))
                .foregroundStyle(BombTheme.yellow)
        }
        .frame(width: 50, height: 50)
        .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private var progressColor: Color {
        member.showsNudge ? BombTheme.red : BombTheme.ink
    }
}

private struct PokeActionButton: View {
    let onPoke: (PokeStyle) -> Int?

    @State private var suppressNextTap = false
    @State private var lightFeedbackID = 0
    @State private var heavyFeedbackID = 0
    @State private var showsBomb = false
    @State private var showsLimitAlert = false
    @State private var isCoolingDown = false
    @State private var isCharging = false
    @State private var hasChargedBomb = false
    @State private var showsExplosion = false

    var body: some View {
        ZStack {
            Label(isCoolingDown ? "讓他喘口氣" : "戳一下", systemImage: "hand.tap.fill")
                .font(.caption.weight(.black))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(BombTheme.ink)
                .clipShape(.capsule)
                .scaleEffect(isCharging ? 0.92 : 1)
                .rotationEffect(.degrees(isCharging ? 2 : 0))
                .animation(
                    isCharging ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .snappy,
                    value: isCharging
                )
                .contentShape(.capsule)
                .onTapGesture {
                    guard !suppressNextTap, !isCoolingDown else { return }
                    sendPoke(style: .gentle, isBombPoke: false)
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    guard !isCoolingDown else { return }
                    suppressNextTap = true
                    hasChargedBomb = true
                    sendPoke(style: .alarm, isBombPoke: true)
                } onPressingChanged: { isPressing in
                    guard !isCoolingDown else { return }
                    isCharging = isPressing

                    guard !isPressing, hasChargedBomb else { return }
                    hasChargedBomb = false
                    showsBomb = false
                    showsExplosion = true

                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        showsExplosion = false
                        suppressNextTap = false
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    guard !isCoolingDown else { return }
                    sendPoke(style: .gentle, isBombPoke: false)
                }

            Text("💣")
                .font(.system(size: 52))
                .offset(y: -58)
                .scaleEffect(showsBomb ? 1 : 0.1)
                .opacity(showsBomb ? 1 : 0)
                .allowsHitTesting(false)

            Text("💥")
                .font(.system(size: 62))
                .offset(y: -58)
                .scaleEffect(showsExplosion ? 1 : 0.1)
                .opacity(showsExplosion ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.bouncy, value: showsBomb)
        .animation(.snappy, value: showsExplosion)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedbackID)
        .sensoryFeedback(.impact(weight: .heavy), trigger: heavyFeedbackID)
        .alert("讓他喘口氣>_<", isPresented: $showsLimitAlert) {
            Button("好", role: .cancel) { }
        }
    }

    private func sendPoke(style: PokeStyle, isBombPoke: Bool) {
        guard let pokeCount = onPoke(style) else { return }

        if isBombPoke {
            heavyFeedbackID += 1
            showsBomb = true
        } else {
            lightFeedbackID += 1
        }

        if pokeCount == 15 {
            showsLimitAlert = true
            isCoolingDown = true
            Task {
                try? await Task.sleep(for: .seconds(10))
                isCoolingDown = false
            }
        }
    }
}

#Preview("Member progress card") {
    ZStack {
        BombTheme.yellow.ignoresSafeArea()
        MemberProgressCard(
            member: MemberProgressPreviewItem(
                id: "mimi",
                name: "米米",
                role: "簡報設計",
                progress: 45,
                currentTask: "簡報視覺統整",
                status: "進度落後",
                showsNudge: true
            ),
            onPoke: { _ in 1 }
        )
        .padding(20)
    }
}
