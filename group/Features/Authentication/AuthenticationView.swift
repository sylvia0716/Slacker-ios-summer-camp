import SwiftUI

/// Group Bomb 的 Email/Password 登入與註冊入口。
struct AuthenticationView: View {
    let session: AuthSessionStore

    @State private var mode = AuthenticationMode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var localErrorMessage: String?
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
        .onChange(of: mode) { _, _ in
            localErrorMessage = nil
            session.clearError()
        }
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

            Text("GROUP BOMB")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            Text(mode == .signIn ? "登入後繼續拆彈" : "建立你的拆彈手帳號")
                .font(.headline)
        }
        .foregroundStyle(BombTheme.ink)
    }

    private var formCard: some View {
        VStack(spacing: 18) {
            Picker("登入模式", selection: $mode) {
                ForEach(AuthenticationMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 12) {
                authenticationField(
                    title: "電子郵件",
                    symbol: "envelope.fill",
                    text: $email,
                    field: .email,
                    isSecure: false
                )
                authenticationField(
                    title: "密碼",
                    symbol: "lock.fill",
                    text: $password,
                    field: .password,
                    isSecure: true
                )

                if mode == .register {
                    authenticationField(
                        title: "再次輸入密碼",
                        symbol: "lock.rotation",
                        text: $passwordConfirmation,
                        field: .passwordConfirmation,
                        isSecure: true
                    )
                }
            }

            if let message = localErrorMessage ?? session.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                submit()
            } label: {
                SwiftUI.Group {
                    if session.isWorking {
                        ProgressView().tint(BombTheme.yellow)
                    } else {
                        Label(mode.actionTitle, systemImage: mode.actionSymbol)
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
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
            }
            .focused($focusedField, equals: field)
            .textContentType(field == .email ? .emailAddress : (mode == .register ? .newPassword : .password))
            .submitLabel(field == .email ? .next : .done)
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
        localErrorMessage = nil
        session.clearError()

        if mode == .register, password != passwordConfirmation {
            localErrorMessage = "兩次輸入的密碼不一致。"
            return
        }

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
    case passwordConfirmation
}
