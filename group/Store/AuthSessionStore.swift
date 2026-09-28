import FirebaseAuth
import FirebaseCore
import Foundation
import Observation

/// Firebase 匿名與 Email/Password 帳號的單一登入狀態來源。
@MainActor @Observable
final class AuthSessionStore {
    private(set) var currentUserID: String?
    private(set) var currentUserEmail: String?
    private(set) var isAnonymous = false
    private(set) var isCheckingSession = true
    private(set) var isWorking = false
    private var developerAccess = DeveloperAccessState()
    var isInternalDeveloper: Bool { isAuthenticated && developerAccess.isAllowed && developerAccess.uid == currentUserID }
    @ObservationIgnored private var developerAccessTask: Task<Void, Never>?
    var language: AppLanguage {
        get { AppLanguageSettings.shared.language }
        set { AppLanguageSettings.shared.preference = AppLanguagePreference(rawValue: newValue.rawValue)! }
    }
    private var signOutErrorKey: String?
    var signOutErrorMessage: String? { signOutErrorKey.map { text($0) } }
    private var errorKey: String?
    var errorMessage: String? { errorKey.map { text($0) } }

    func text(_ key: String) -> String { language.text(key) }

    @ObservationIgnored private var authStateHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isStartingAnonymousSession = false
    private var hasEnteredAnonymousSession = false
    private(set) var isPreviewSession = false
    @ObservationIgnored private var onUserChange: ((String?) -> Void)?

    /// 已綁定 Email/Password、可在其他裝置登入的正式帳號。
    var isAuthenticated: Bool { currentUserID != nil && !isAnonymous && !isPreviewSession }
    /// 臨時帳號保留原本的 UID 與資料，但要由登入頁明確選擇後才進入。
    var canEnterApp: Bool { isAuthenticated || isPreviewSession || (isAnonymous && hasEnteredAnonymousSession) }

    /// App 啟動且 Firebase 完成設定後才開始監聽，避免缺少 plist 時存取 Auth 而閃退。
    func start(onUserChange: ((String?) -> Void)? = nil) {
        self.onUserChange = onUserChange
        guard !hasStarted else { return }
        hasStarted = true

        guard FirebaseApp.app() != nil else {
            isCheckingSession = false
            errorKey = "Firebase 尚未設定完成，請確認 GoogleService-Info.plist 已加入 group target。"
            return
        }

        let auth = Auth.auth()
        authStateHandle = auth.addIDTokenDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                guard user?.uid == auth.currentUser?.uid else { return }
                if user == nil, self.isStartingAnonymousSession { return }
                self.updateSession(user: user)
            }
        }

        updateSession(user: auth.currentUser)
    }

    /// 建立此裝置的臨時 Firebase 身分。若失敗，可由登入頁再次呼叫重試。
    func startAnonymousSession() async {
        guard !isWorking else { return }
        guard FirebaseApp.app() != nil else {
            isCheckingSession = false
            errorKey = "Firebase 尚未設定完成，請稍後再試。"
            return
        }
        guard Auth.auth().currentUser == nil else {
            hasEnteredAnonymousSession = Auth.auth().currentUser?.isAnonymous == true
            updateSession(user: Auth.auth().currentUser)
            return
        }

        isStartingAnonymousSession = true
        isCheckingSession = true
        isWorking = true
        errorKey = nil
        defer {
            isStartingAnonymousSession = false
            isCheckingSession = false
            isWorking = false
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            hasEnteredAnonymousSession = true
            updateSession(user: result.user)
        } catch {
            updateSession(user: nil)
            errorKey = Self.localizedMessage(for: error)
        }
    }

    func signIn(email: String, password: String) async {
        guard !isWorking else { return }
        guard validate(email: email, password: password) else { return }
        guard FirebaseApp.app() != nil else {
            errorKey = "Firebase 尚未設定完成，請稍後再試。"
            return
        }

        isWorking = true
        errorKey = nil
        defer {
            isWorking = false
            PokeRepository.resumeDeviceRegistration()
        }

        do {
            try await PokeRepository().prepareForAccountChange()
            let result = try await Auth.auth().signIn(
                withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            updateSession(user: result.user)
        } catch {
            errorKey = Self.localizedMessage(for: error)
        }
    }

    func register(email: String, password: String) async {
        guard !isWorking else { return }
        guard validate(email: email, password: password) else { return }
        guard FirebaseApp.app() != nil else {
            errorKey = "Firebase 尚未設定完成，請稍後再試。"
            return
        }

        isWorking = true
        errorKey = nil
        defer { isWorking = false }

        do {
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: AuthDataResult
            if let user = Auth.auth().currentUser, user.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: normalizedEmail, password: password)
                result = try await user.link(with: credential)
            } else {
                result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            }
            updateSession(user: result.user)
        } catch {
            errorKey = Self.localizedMessage(for: error)
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        guard !isWorking else { return false }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            errorKey = "請輸入有效的電子郵件地址。"
            return false
        }
        guard FirebaseApp.app() != nil else {
            errorKey = "Firebase 尚未設定完成，請稍後再試。"
            return false
        }

        isWorking = true
        errorKey = nil
        defer { isWorking = false }

        do {
            let auth = Auth.auth()
            auth.languageCode = language.firebaseLanguageCode
            try await auth.sendPasswordReset(withEmail: normalizedEmail)
            return true
        } catch {
            errorKey = Self.localizedMessage(for: error)
            return false
        }
    }

#if DEBUG
    /// 本機 UI 驗證專用；不建立 Firebase 帳號，也不會出現在正式版本。
    func enterPreviewSession() {
        updateSession(userID: nil, email: nil, isAnonymous: false)
        isPreviewSession = true
        updateSession(userID: "debug-preview", email: "preview@local", isAnonymous: false)
        errorKey = nil
    }
#endif

    func signOut() {
#if DEBUG
        if isPreviewSession {
            isPreviewSession = false
            updateSession(userID: nil, email: nil, isAnonymous: false)
            errorKey = nil
            return
        }
#endif
        guard FirebaseApp.app() != nil, !isWorking else { return }
        signOutErrorKey = nil
        isWorking = true
        Task {
            defer {
                isWorking = false
                PokeRepository.resumeDeviceRegistration()
            }
            do {
                try await PokeRepository().prepareForAccountChange()
                try Auth.auth().signOut()
                updateSession(user: nil)
                errorKey = nil
            } catch {
                isStartingAnonymousSession = false
                isCheckingSession = false
                signOutErrorKey = Self.localizedMessage(for: error)
            }
        }
    }

    /// 從背景回到 App 時，未綁定帳號者先回入口；不刪除臨時帳號的雲端資料。
    func returnToEntryIfUnauthenticated() {
        guard !isAuthenticated, !isPreviewSession else { return }
        hasEnteredAnonymousSession = false
    }

    func clearError() {
        errorKey = nil
    }

    /// Called on login/token changes and foregrounding. Credentials and claims are never logged.
    func refreshDeveloperAccess(forceRefresh: Bool = false) {
        developerAccessTask?.cancel()
        let request = developerAccess.begin(uid: currentUserID, email: currentUserEmail, isAnonymous: isAnonymous)
        guard isAuthenticated, FirebaseApp.app() != nil,
              let user = Auth.auth().currentUser, user.uid == currentUserID else {
            developerAccess.finish(request: request, claims: nil)
            return
        }
        developerAccessTask = Task { [weak self] in
            let result = try? await user.getIDTokenResult(forcingRefresh: forceRefresh)
            guard let self, !Task.isCancelled, self.currentUserID == user.uid,
                  Auth.auth().currentUser?.uid == user.uid else { return }
            self.developerAccess.finish(request: request, claims: result?.claims)
        }
    }

    private func validate(email: String, password: String) -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            errorKey = "請輸入有效的電子郵件地址。"
            return false
        }
        guard password.count >= 6 else {
            errorKey = "密碼至少需要 6 個字元。"
            return false
        }
        return true
    }

    private func updateSession(user: User?) {
        updateSession(userID: user?.uid, email: user?.email, isAnonymous: user?.isAnonymous ?? false)
    }

    private func updateSession(userID: String?, email: String?, isAnonymous: Bool) {
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
        self.isAnonymous = isAnonymous
        if !isAnonymous { hasEnteredAnonymousSession = false }
        isCheckingSession = false
        refreshDeveloperAccess()
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
            "這個登入方式尚未啟用，請先到 Firebase Console 開啟。"
        case .invalidAPIKey, .appNotAuthorized:
            "Firebase 設定有誤，請確認 App 設定檔。"
        default:
            "目前無法完成操作，請稍後再試。"
        }
    }
}
