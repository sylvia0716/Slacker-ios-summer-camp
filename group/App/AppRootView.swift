import SwiftUI
import Combine

/// App shell: owns the prototype's shared store and the primary app navigation.
struct AppRootView: View {
    @State private var store = GroupBombModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var authSession = AuthSessionStore()
    @State private var tab = AppTab.groups
    @State private var settingsNavigationID = UUID()
    @State private var tutorialStep: TutorialStep?
    @State private var isBombTabBarHidden = false
    @State private var safeAreaInsets = EdgeInsets()
    @State private var activePokeReception: PokeReception?
    @State private var pokePresentationID = 0
    @State private var reviewNotificationPath: [ReviewNotificationRoute] = []
    private let reviewRouter = ReviewNotificationRouter.shared

    var body: some View {
        SwiftUI.Group {
            if authSession.isCheckingSession {
                authenticationLoadingView
            } else if authSession.canEnterApp, store.firebaseUID == authSession.currentUserID {
                authenticatedContent
                    .id(authSession.currentUserID)
            } else {
                AuthenticationView(session: authSession)
            }
        }
        .environment(\.locale, L10n.locale)
        .environment(\.bombSafeAreaInsets, safeAreaInsets)
        .onGeometryChange(for: EdgeInsets.self) { proxy in
            proxy.safeAreaInsets
        } action: { insets in
            safeAreaInsets = insets
        }
        .task {
            WidgetSnapshotStore.updateLanguage()
            authSession.start { uid in store.changeCloudAccount(to: uid) }
            store.changeCloudAccount(to: authSession.currentUserID)
            if scenePhase == .active { store.resumeCloudSync() }
        }
        .onChange(of: authSession.currentUserID) { _, _ in
            reviewNotificationPath = []
            if scenePhase == .active { store.resumeCloudSync() }
            openPendingReview()
        }
        .onChange(of: reviewRouter.pending) { _, _ in openPendingReview() }
        .onChange(of: authSession.isCheckingSession) { _, _ in openPendingReview() }
        .onChange(of: store.isLoadingCloudGroups) { _, _ in openPendingReview() }
        .onChange(of: store.groups) { _, _ in openPendingReview() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AppLanguageSettings.shared.refreshSystemLanguage()
                store.resumeCloudSync()
            }
            else if phase == .background {
                store.suspendCloudSync()
                if !store.isDemoMode { PokeBackgroundRefresh.shared.schedule() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            AppLanguageSettings.shared.refreshSystemLanguage()
        }
        .onChange(of: AppLanguageSettings.shared.preference) { _, _ in
            WidgetSnapshotStore.updateLanguage()
        }
        .onChange(of: AppLanguageSettings.shared.language) { _, _ in
            store.registerPokeDevice()
            store.refreshDeadlineReminders()
        }
        .onDisappear { store.suspendCloudSync() }
        .onReceive(NotificationCenter.default.publisher(for: .pokeReceived)) { notification in
            guard store.receivesPokes, let reception = notification.object as? PokeReception else { return }
            pokePresentationID += 1
            activePokeReception = reception
        }
        .onReceive(NotificationCenter.default.publisher(for: .pokePushTokenUpdated)) { _ in
            store.registerPokeDevice()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationAuthorizationUpdated)) { _ in
            store.refreshDeadlineReminders()
        }
        .overlay {
            if let activePokeReception {
                PokeReceptionOverlay(reception: activePokeReception) {
                    self.activePokeReception = nil
                }
                .id(pokePresentationID)
            }
        }
        .overlay {
            if let message = store.cloudErrorMessage {
                cloudSyncErrorOverlay(message: message)
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .animation(.snappy, value: store.cloudErrorMessage != nil)
    }

    private func cloudSyncErrorOverlay(message: String) -> some View {
        ZStack {
            BombTheme.ink.opacity(0.48)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Label(L10n.text("雲端同步"), systemImage: "icloud.slash.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(BombTheme.red)

                Text(message)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BombTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(L10n.text("關閉")) {
                        withAnimation(.snappy) {
                            store.cloudErrorMessage = nil
                        }
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                    .buttonStyle(.plain)

                    Button(L10n.text("重試")) {
                        withAnimation(.snappy) {
                            store.cloudErrorMessage = nil
                        }
                        Task { await store.reloadCloudGroups() }
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
        }
    }

    private var authenticatedContent: some View {
        ZStack {
            NavigationStack(path: $reviewNotificationPath) {
                GroupListView(
                    model: store,
                    isSelected: tab == .groups,
                    tutorialStep: $tutorialStep,
                    onReplayTutorial: replayTutorial
                )
                .navigationDestination(for: ReviewNotificationRoute.self) { route in
                    if let group = store.groups.first(where: { $0.id == route.groupID }) {
                        GroupDetailView(group: group, model: store, opensPeerReview: true)
                    }
                }
            }
            .opacity(tab == .groups ? 1 : 0)
            .allowsHitTesting(tab == .groups)
            .accessibilityHidden(tab != .groups)
            .transformPreference(BombTabBarHiddenPreferenceKey.self) { hidden in
                if tab != .groups { hidden = false }
            }

            NavigationStack {
                MyTasksView(model: store, isSelected: tab == .myTasks)
            }
                .opacity(tab == .myTasks ? 1 : 0)
                .allowsHitTesting(tab == .myTasks)
                .accessibilityHidden(tab != .myTasks)
                .transformPreference(BombTabBarHiddenPreferenceKey.self) { hidden in
                    if tab != .myTasks { hidden = false }
                }

            NavigationStack {
                SettingsView(
                    model: store,
                    authSession: authSession,
                    onReplayTutorial: replayTutorial
                )
            }
            .id(settingsNavigationID)
            .opacity(tab == .settings ? 1 : 0)
            .allowsHitTesting(tab == .settings)
            .accessibilityHidden(tab != .settings)
            .transformPreference(BombTabBarHiddenPreferenceKey.self) { hidden in
                if tab != .settings { hidden = false }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isBombTabBarHidden {
                BombTabBar(selection: $tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: tab) { oldTab, _ in
            if oldTab == .settings { settingsNavigationID = UUID() }
        }
        .onPreferenceChange(BombTabBarHiddenPreferenceKey.self) { hidden in
            withAnimation(.snappy) { isBombTabBarHidden = hidden }
        }
        .overlayPreferenceValue(TutorialTargetPreferenceKey.self) { targetAnchors in
            GeometryReader { proxy in
                if tutorialStep != nil {
                    OnboardingTutorialView(
                        step: $tutorialStep,
                        targets: tutorialFrames(from: targetAnchors, in: proxy),
                        onFinish: finishTutorial,
                        onSkip: finishTutorial
                    )
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            presentTutorialIfNeeded()
        }
    }

    private var authenticationLoadingView: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .tint(BombTheme.ink)
        }
    }

    private func openPendingReview() {
        guard let destination = reviewRouter.pending, !authSession.isCheckingSession else { return }
        guard destination.uid == authSession.currentUserID else {
            reviewRouter.pending = nil
            return
        }
        guard store.firebaseUID == destination.uid, !store.isLoadingCloudGroups else { return }
        guard let group = store.groups.first(where: { $0.id == destination.groupID }),
              group.memberIDs.contains(store.currentUserID) else { return }
        reviewRouter.pending = nil
        tab = .groups
        tutorialStep = nil
        guard !store.hasCompletedReviewReminders(in: group) else { return }
        reviewNotificationPath = [ReviewNotificationRoute(groupID: group.id)]
    }

    private func tutorialFrames(
        from targets: [TutorialTarget: Anchor<CGRect>],
        in proxy: GeometryProxy
    ) -> [TutorialTarget: CGRect] {
        targets.mapValues { proxy[$0] }
    }

    private func finishTutorial() {
        if let userID = authSession.currentUserID {
            UserDefaults.standard.set(true, forKey: onboardingKey(for: userID))
        }
        tutorialStep = nil
    }

    private func replayTutorial() {
        tab = .groups
        tutorialStep = .welcome
    }

    private func presentTutorialIfNeeded() {
        guard let userID = authSession.currentUserID,
              !UserDefaults.standard.bool(forKey: onboardingKey(for: userID)),
              tutorialStep == nil else { return }

        tab = .groups
        tutorialStep = .welcome
    }

    private func onboardingKey(for userID: String) -> String {
        "hasCompletedOnboarding.\(userID)"
    }
}

#Preview { AppRootView() }
