import SwiftUI

/// Shared appearance for app-owned alerts and confirmations.
extension View {
    func bombDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .visible,
        destructiveIsRed: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZStack {
                BombTheme.ink.opacity(0.4).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(title)
                            .font(.title2.weight(.black))
                            .accessibilityAddTraits(.isHeader)
                        message()
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) { actions() }
                            .buttonStyle(BombDialogButtonStyle(
                                destructiveIsRed: destructiveIsRed,
                                dismiss: { isPresented.wrappedValue = false }
                            ))
                    }
                    .foregroundStyle(BombTheme.ink)
                    .padding(24)
                    .frame(maxWidth: 360)
                    .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center)
            }
            .presentationBackground(.clear)
            .interactiveDismissDisabled()
        }
    }

    func bombDialog<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .visible,
        destructiveIsRed: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        bombDialog(title, isPresented: isPresented, destructiveIsRed: destructiveIsRed,
                   actions: actions, message: { EmptyView() })
    }
}

private struct BombDialogButtonStyle: PrimitiveButtonStyle {
    let destructiveIsRed: Bool
    let dismiss: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        Button {
            // Run while the selected item still exists; dismissal bindings may clear it.
            configuration.trigger()
            dismiss()
        } label: {
            configuration.label
                .font(.headline.weight(.black))
                .foregroundStyle(configuration.role == .destructive && destructiveIsRed ? BombTheme.paper : BombTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, 12)
                .background(background(for: configuration.role), in: Capsule())
                .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func background(for role: ButtonRole?) -> Color {
        if role == .cancel { return BombTheme.paper }
        if role == .destructive && destructiveIsRed { return BombTheme.red }
        return BombTheme.yellow
    }
}
