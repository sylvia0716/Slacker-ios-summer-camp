import SwiftUI

/// Oops Bomb 的 Email/Password 登入與註冊入口。
struct AuthenticationView: View {
    let session: AuthSessionStore

    @State private var mode = AuthenticationMode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isPasswordResetPresented = false
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    brandHeader
                    formCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.locale, Locale(identifier: session.language.rawValue))
        .onChange(of: mode) { _, _ in
            isPasswordVisible = false
            session.clearError()
        }
        .sheet(isPresented: $isPasswordResetPresented) {
            PasswordResetView(session: session, initialEmail: email)
        }
    }

    private var languageMenu: some View {
        Menu {
            Picker("Language / 語言", selection: Binding(
                get: { session.language },
                set: { session.language = $0 }
            )) {
                Text("中文").tag(AppLanguage.traditionalChinese)
                Text("English").tag(AppLanguage.english)
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .foregroundStyle(BombTheme.ink)
        .accessibilityLabel("Language / 語言")
        .disabled(session.isWorking)
    }

    private var modeSwitch: some View {
        HStack(spacing: 3) {
            ForEach(AuthenticationMode.allCases) { option in
                Button {
                    focusedField = nil
                    withAnimation(.snappy(duration: 0.18)) { mode = option }
                } label: {
                    Text(session.text(option.title))
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(mode == option ? BombTheme.ink : BombTheme.paper)
                        .background(mode == option ? BombTheme.yellow : .clear, in: Capsule())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(BombTheme.ink, in: Capsule())
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.60 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.text("登入模式"))
        .disabled(session.isWorking)
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(BombTheme.yellow)
                .frame(width: 94, height: 94)
                .background(BombTheme.ink)
                .clipShape(.circle)
                .overlay(Circle().stroke(BombTheme.paper, lineWidth: 5))
                .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)

            Text(session.text("Oops Bomb"))
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            Text(session.text("一起拆彈，一起過關。"))
                .multilineTextAlignment(.center)
                .font(.headline)
        }
        .foregroundStyle(BombTheme.ink)
    }

    private var formCard: some View {
        VStack(spacing: 18) {
            modeSwitch
                .padding(.top, 12)

            VStack(spacing: 12) {
                authenticationField(
                    title: session.text("電子郵件"),
                    symbol: "envelope.fill",
                    text: $email,
                    field: .email,
                    isSecure: false
                )
                authenticationField(
                    title: session.text("密碼"),
                    symbol: "lock.fill",
                    text: $password,
                    field: .password,
                    isSecure: true
                )

            }
            .padding(.horizontal, 16)

            HStack(spacing: 4) {
                Spacer(minLength: 0)
                languageMenu
                if mode == .signIn {
                    Button(session.text("忘記密碼？")) {
                        focusedField = nil
                        session.clearError()
                        isPasswordResetPresented = true
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BombTheme.ink)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .disabled(session.isWorking)
                }
            }

            if let message = session.errorMessage {
                Label(session.text(message), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                submit()
            } label: {
                SwiftUI.Group {
                    if session.isWorking {
                        ProgressView().tint(BombTheme.paper)
                    } else {
                        Label(session.text(mode.actionTitle), systemImage: mode.actionSymbol)
                    }
                }
                .font(.headline.weight(.black))
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.60 }
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BombTheme.paper)
            .background(BombTheme.ink)
            .clipShape(.capsule)
            .disabled(session.isWorking)

#if DEBUG
            Button(session.text("不登入，直接預覽 App")) {
                focusedField = nil
                session.enterPreviewSession()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(BombTheme.ink)
            .buttonStyle(.plain)
#endif
        }
        .comicCard()
    }

    private func authenticationField(
        title: String,
        symbol: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)

            SwiftUI.Group {
                if isSecure && !isPasswordVisible {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(isSecure ? .default : .emailAddress)
                }
            }
            .focused($focusedField, equals: field)
            .textContentType(field == .email ? .emailAddress : (mode == .register ? .newPassword : .password))
            .submitLabel(field == .email ? .next : .done)
            .autocorrectionDisabled()

            if isSecure {
                Button {
                    isPasswordVisible.toggle()
                    focusedField = field
                } label: {
                    SwiftUI.Group {
                        if isPasswordVisible {
                            ClosedEyeIcon()
                                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 23, height: 23)
                        } else {
                            Image(systemName: "eye")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                        .foregroundStyle(BombTheme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.text(isPasswordVisible ? "隱藏密碼" : "顯示密碼"))
            }
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))
    }

    private func submit() {
        focusedField = nil
        session.clearError()

        Task {
            switch mode {
            case .signIn:
                await session.signIn(email: email, password: password)
            case .register:
                await session.register(email: email, password: password)
            }
        }
    }
}

struct PasswordResetView: View {
    let completionTitle: String
    let session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var isSent = false
    @FocusState private var isEmailFocused: Bool

    init(session: AuthSessionStore, initialEmail: String, completionTitle: String = "返回登入") {
        self.completionTitle = completionTitle
        self.session = session
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isSent {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 44, weight: .black))
                        Text(session.text("重設信已寄出"))
                            .font(.title2.weight(.black))
                        Text(session.text("若此信箱已註冊，請從信件中的連結設定新密碼。"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BombTheme.ink.opacity(0.65))
                            .multilineTextAlignment(.center)

                        Button(session.text(completionTitle)) { dismiss() }
                            .font(.headline.weight(.black))
                            .foregroundStyle(BombTheme.yellow)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(BombTheme.ink)
                            .clipShape(.capsule)
                    } else {
                        Text(session.text("輸入註冊時使用的電子郵件，我們會寄送密碼重設連結。"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BombTheme.ink.opacity(0.65))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .frame(width: 24)
                            TextField(session.text("電子郵件"), text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .focused($isEmailFocused)
                                .submitLabel(.send)
                                .onSubmit(sendResetEmail)
                        }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 14)

                        .frame(height: 52)
                        .background(.white.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))

                        if let message = session.errorMessage {
                            Label(session.text(message), systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(BombTheme.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: sendResetEmail) {
                            SwiftUI.Group {
                                if session.isWorking {
                                    ProgressView().tint(BombTheme.yellow)
                                } else {
                                    Label(session.text("寄送重設信"), systemImage: "paperplane.fill")
                                }
                            }
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(BombTheme.yellow)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                        .disabled(session.isWorking)
                    }
                }
                .foregroundStyle(BombTheme.ink)
                .padding(20)
            }
            .navigationTitle(session.text("忘記密碼"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.text("取消")) { dismiss() }
                        .disabled(session.isWorking)
                }
            }
        }

        .interactiveDismissDisabled(session.isWorking)
        .presentationDetents([.medium, .large])
        .presentationBackground(BombTheme.paper)
        .onAppear {
            session.clearError()
            isEmailFocused = email.isEmpty
        }
    }

    private func sendResetEmail() {
        guard !session.isWorking else { return }
        isEmailFocused = false
        Task {
            if await session.sendPasswordReset(email: email) {
                isSent = true
            }
        }
    }
}

private enum AuthenticationMode: String, CaseIterable, Identifiable {
    case signIn
    case register

    var id: Self { self }
    var title: String { self == .signIn ? "登入" : "註冊" }
    var actionTitle: String { self == .signIn ? "登入" : "建立帳號" }
    var actionSymbol: String { self == .signIn ? "arrow.right.circle.fill" : "person.crop.circle.badge.plus" }
}

private enum Field: Hashable {
    case email
    case password
}

/// Matches the eyelid and lashes used on the password reset web page.
private struct ClosedEyeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3, y: 9))
        path.addCurve(to: CGPoint(x: 12, y: 15), control1: CGPoint(x: 3, y: 9), control2: CGPoint(x: 6, y: 15))
        path.addCurve(to: CGPoint(x: 21, y: 9), control1: CGPoint(x: 18, y: 15), control2: CGPoint(x: 21, y: 9))
        for (start, end) in [
            (CGPoint(x: 5, y: 12), CGPoint(x: 3, y: 15)),
            (CGPoint(x: 9, y: 14), CGPoint(x: 8, y: 18)),
            (CGPoint(x: 15, y: 14), CGPoint(x: 16, y: 18)),
            (CGPoint(x: 19, y: 12), CGPoint(x: 21, y: 15))
        ] {
            path.move(to: start)
            path.addLine(to: end)
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
