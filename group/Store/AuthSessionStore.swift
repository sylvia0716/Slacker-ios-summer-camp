import FirebaseAuth
import FirebaseCore
import Foundation
import Observation

/// Firebase Email/Password 的單一登入狀態來源。
@MainActor @Observable
final class AuthSessionStore {
    private(set) var currentUserID: String?
    private(set) var currentUserEmail: String?
    private(set) var isCheckingSession = true
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private var authStateHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var hasStarted = false
#if DEBUG
    @ObservationIgnored private var isPreviewSession = false
#endif
    @ObservationIgnored private var onUserChange: ((String?) -> Void)?

    var isAuthenticated: Bool { currentUserID != nil }

    /// App 啟動且 Firebase 完成設定後才開始監聽，避免缺少 plist 時存取 Auth 而閃退。
    func start(onUserChange: ((String?) -> Void)? = nil) {
        self.onUserChange = onUserChange
        guard !hasStarted else { return }
        hasStarted = true

        guard FirebaseApp.app() != nil else {
            isCheckingSession = false
            errorMessage = "Firebase 尚未設定完成，請確認 GoogleService-Info.plist 已加入 group target。"
            return
        }

        let auth = Auth.auth()
        updateSession(userID: auth.currentUser?.uid, email: auth.currentUser?.email)
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            let userID = user?.uid
            let email = user?.email
            Task { @MainActor in
                self?.updateSession(userID: userID, email: email)
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard validate(email: email, password: password) else { return }
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase 尚未設定完成，請稍後再試。"
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await Auth.auth().signIn(
                withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            updateSession(userID: result.user.uid, email: result.user.email)
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    func register(email: String, password: String) async {
        guard validate(email: email, password: password) else { return }
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase 尚未設定完成，請稍後再試。"
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await Auth.auth().createUser(
                withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            updateSession(userID: result.user.uid, email: result.user.email)
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            errorMessage = "請輸入有效的電子郵件地址。"
            return false
        }
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase 尚未設定完成，請稍後再試。"
            return false
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
            return true
        } catch {
            errorMessage = Self.localizedMessage(for: error)
            return false
        }
    }

#if DEBUG
    /// 本機 UI 驗證專用；不建立 Firebase 帳號，也不會出現在正式版本。
    func enterPreviewSession() {
        isPreviewSession = true
        updateSession(userID: "debug-preview", email: "preview@local")
        errorMessage = nil
    }
#endif

    func signOut() {
#if DEBUG
        if isPreviewSession {
            isPreviewSession = false
            updateSession(userID: nil, email: nil)
            errorMessage = nil
            return
        }
#endif
        guard FirebaseApp.app() != nil else { return }

        do {
            try Auth.auth().signOut()
            updateSession(userID: nil, email: nil)
            errorMessage = nil
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func validate(email: String, password: String) -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            errorMessage = "請輸入有效的電子郵件地址。"
            return false
        }
        guard password.count >= 6 else {
            errorMessage = "密碼至少需要 6 個字元。"
            return false
        }
        return true
    }

    private func updateSession(userID: String?, email: String?) {
#if DEBUG
        if isPreviewSession, userID == nil {
            isCheckingSession = false
            return
        }
#endif
        // 此 UID 直接來自 Firebase Auth；不以本機 UUID 或電子郵件代替。
        if userID != currentUserID { onUserChange?(userID) }
        currentUserID = userID
        currentUserEmail = email
        isCheckingSession = false
    }

    private static func localizedMessage(for error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .invalidEmail:
            "電子郵件格式不正確。"
        case .emailAlreadyInUse:
            "這個電子郵件已經註冊，請直接登入。"
        case .weakPassword:
            "密碼強度不足，請使用至少 6 個字元。"
        case .wrongPassword, .userNotFound, .invalidCredential:
            "電子郵件或密碼不正確。"
        case .userDisabled:
            "這個帳號已被停用，請聯絡管理員。"
        case .tooManyRequests:
            "嘗試次數過多，請稍後再試。"
        case .networkError:
            "網路連線異常，請確認網路後再試。"
        case .keychainError:
            "無法儲存登入狀態，請重新安裝 App 後再試。"
        case .operationNotAllowed:
            "Email／Password 登入尚未啟用，請先到 Firebase Console 開啟。"
        case .invalidAPIKey, .appNotAuthorized:
            "Firebase 設定有誤，請確認 App 設定檔。"
        default:
            "目前無法完成操作，請稍後再試。"
        }
    }
}
