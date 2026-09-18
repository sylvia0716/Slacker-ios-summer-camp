import SwiftUI

/// Full-screen feedback shown to the teammate receiving a poke while the app is open.
struct PokeReceptionOverlay: View {
    let reception: PokeReception
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isWobbling = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(effectColor.opacity(0.8), lineWidth: 7)
                        .frame(width: 160, height: 160)
                        .scaleEffect(isPulsing ? 1.35 : 0.7)
                        .opacity(isPulsing ? 0 : 1)

                    Text(effectSymbol)
                        .font(.system(size: 88))
                        .rotationEffect(.degrees(isWobbling ? 8 : -8))
                        .scaleEffect(isPulsing ? 1.05 : 0.88)
                }
                .frame(height: 150)

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("\(reception.groupName) 的隊友正在找你")
                        .font(.headline.weight(.bold))
                    Text(countMessage)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(effectColor)
                }
                .multilineTextAlignment(.center)

                Button("我回來了", action: onDismiss)
                    .font(.headline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: 4)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(headline)，\(reception.groupName)，\(countMessage)")
        .task {
            guard !reduceMotion else { return }

            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
            withAnimation(.bouncy(duration: 0.25).repeatForever(autoreverses: true)) {
                isWobbling = true
            }
        }
    }

    private var effectSymbol: String {
        switch reception.style {
        case .gentle: "👋"
        case .meme: "😵‍💫"
        case .alarm: "🚨"
        }
    }

    private var headline: String {
        switch reception.style {
        case .gentle: "有人戳你一下"
        case .meme: "你被迷因轟炸了"
        case .alarm: "進度警報！"
        }
    }

    private var countMessage: String {
        "這是第 \(reception.pokeCount) 下提醒"
    }

    private var effectColor: Color {
        switch reception.style {
        case .gentle: BombTheme.green
        case .meme: .purple
        case .alarm: BombTheme.red
        }
    }
}

#Preview {
    PokeReceptionOverlay(
        reception: PokeReception(groupName: "期末專案", pokeCount: 3, style: .alarm),
        onDismiss: { }
    )
}
