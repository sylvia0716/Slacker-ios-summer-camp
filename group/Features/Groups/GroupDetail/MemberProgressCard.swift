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
                    Button(action: {}) {
                        Label("戳一下", systemImage: "hand.tap.fill")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .foregroundStyle(.white)
                            .background(BombTheme.ink)
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("提醒功能將在下一階段開放")
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
            )
        )
        .padding(20)
    }
}
