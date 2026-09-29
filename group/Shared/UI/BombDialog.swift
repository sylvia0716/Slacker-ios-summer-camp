import SwiftUI

/// Shared appearance for app-owned alerts and confirmations.
extension View {
    func bombDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .visible,
        destructiveIsRed: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        modifier(BombDialogPresentation(
            title: title,
            isPresented: isPresented,
            titleVisibility: titleVisibility,
            destructiveIsRed: destructiveIsRed,
            actions: actions,
            message: message
        ))
    }

    func bombDialog<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .visible,
        destructiveIsRed: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        bombDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, destructiveIsRed: destructiveIsRed,
                   actions: actions, message: { EmptyView() })
    }
}

/// Keep the system presentation stationary; animate only the scrim and card.
private struct BombDialogPresentation<Actions: View, Message: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let titleVisibility: Visibility
    let destructiveIsRed: Bool
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let message: () -> Message

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentsCover = false
    @State private var isVisible = false
    @State private var isClosing = false

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .fullScreenCover(isPresented: $presentsCover) {
                    dialog
                        .presentationBackground(.clear)
                        .interactiveDismissDisabled()
                        .onAppear {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isVisible = true
                            }
                        }
                }
        }
        .onChange(of: isPresented, initial: true) { _, presented in
            if presented {
                guard !presentsCover else { return }
                isVisible = false
                isClosing = false
                setCoverPresented(true)
            } else if presentsCover {
                close()
            }
        }
    }

    private var dialog: some View {
        ZStack {
            BombTheme.ink.opacity(isVisible ? 0.32 : 0)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if titleVisibility != .hidden {
                        Text(title)
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .accessibilityAddTraits(.isHeader)
                    }
                    message()
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            actions().fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(spacing: 12) { actions() }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(BombDialogButtonStyle(
                        destructiveIsRed: destructiveIsRed,
                        performAndDismiss: { action in close(action: action) }
                    ))
                }
                .foregroundStyle(BombTheme.ink)
                .padding(24)
                .frame(maxWidth: 360)
                .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
                .scaleEffect(reduceMotion || isVisible ? 1 : 0.96)
                .opacity(isVisible ? 1 : 0)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
            .disabled(isClosing)
        }
        .accessibilityAction(.escape) { close() }
    }

    private func setCoverPresented(_ presented: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentsCover = presented
        }
    }

    private func close(action: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeOut(duration: 0.16), completionCriteria: .removed) {
            isVisible = false
        } completion: {
            // Finish the fade before actions clear the message or selected item.
            action?()
            isPresented = false
            setCoverPresented(false)
        }
    }
}

private struct BombDialogButtonStyle: PrimitiveButtonStyle {
    let destructiveIsRed: Bool
    let performAndDismiss: (@escaping () -> Void) -> Void

    func makeBody(configuration: Configuration) -> some View {
        Button {
            // Preserve the selected item until its action has run, and reject repeat taps.
            performAndDismiss { configuration.trigger() }
        } label: {
            configuration.label
                .font(.headline.weight(.black))
                .foregroundStyle(configuration.role == .cancel ? BombTheme.ink : BombTheme.paper)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
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
        return BombTheme.ink
    }
}
