import SwiftUI

/// Shared layout for editable forms, with actions kept outside the scrolling fields.
struct BombFormSheet<Content: View, Actions: View>: View {
    let title: String
    var showsHandle = false
    var backgroundColor: Color = BombTheme.yellow
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHandle {
                Capsule()
                    .fill(BombTheme.ink.opacity(0.35))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .black))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(backgroundColor)
        }
        .foregroundStyle(BombTheme.ink)
        .tint(BombTheme.ink)
        .background(backgroundColor.ignoresSafeArea())
        .overlay {
            if !showsHandle {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(BombTheme.ink, lineWidth: 3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .presentationBackground(backgroundColor)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

struct BombFormActions: View {
    let primaryTitle: String
    var isEnabled = true
    var isBusy = false
    var secondaryTitle = L10n.text("取消")
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(BombFormPrimaryButtonStyle())
                .disabled(!isEnabled || isBusy)
            Button(secondaryTitle, action: onSecondary)
                .font(.subheadline.weight(.black))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .disabled(isBusy)
        }
    }
}

struct BombFormPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(BombTheme.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(BombTheme.ink.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    func bombFormField() -> some View {
        font(.subheadline.weight(.semibold))
            .padding(13)
            .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(BombTheme.ink, lineWidth: 2)
            }
    }
}
