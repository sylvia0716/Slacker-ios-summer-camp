import SwiftUI

struct PokeButtonFeedback: View {
    let emoji: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bombScale = 0.65
    @State private var bombOpacity = 1.0
    @State private var explosionScale = 0.35
    @State private var explosionOpacity = 0.0

    var body: some View {
        ZStack {
            Text("💣")
                .font(.system(size: 52))
                .phaseAnimator(reduceMotion ? [0.0] : [-1.0, 1.0]) { content, phase in
                    content
                        .rotationEffect(.degrees(phase * max(0, bombScale - 0.65) * 5))
                        .scaleEffect(x: 1 + phase * 0.012, y: 1 - phase * 0.012)
                } animation: { _ in
                    .easeInOut(duration: 0.09)
                }
                .scaleEffect(reduceMotion ? 1 : bombScale)
                .opacity(bombOpacity)

            Text("💥")
                .font(.system(size: 62))
                .scaleEffect(reduceMotion ? 1 : explosionScale)
                .opacity(explosionOpacity)
        }
        .frame(width: 76, height: 76)
        .task(id: emoji) {
            if emoji == "💣" {
                guard !reduceMotion else { return }
                // Inflate in springy beats instead of stretching a tiny icon in one sweep.
                withAnimation(.spring(duration: 0.22, bounce: 0.22)) {
                    bombScale = 0.82
                }
                do {
                    try await Task.sleep(for: .seconds(0.24))
                    withAnimation(.spring(duration: 0.46, bounce: 0.16)) {
                        bombScale = 1.1
                    }
                    try await Task.sleep(for: .seconds(0.48))
                    withAnimation(.spring(duration: 0.58, bounce: 0.12)) {
                        bombScale = 1.42
                    }
                } catch {
                    // Releasing cancels the remaining charge beats and starts the burst.
                    return
                }
                return
            }

            // Keep both layers alive so the charged bomb flows into the burst.
            withAnimation(.easeOut(duration: 0.12)) {
                bombOpacity = 0
                explosionOpacity = 1
            }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.2)) {
                explosionScale = 1.2
            }

            do {
                try await Task.sleep(for: .seconds(0.24))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.32)) {
                explosionScale = 1.45
                explosionOpacity = 0
            }
        }
    }
}
