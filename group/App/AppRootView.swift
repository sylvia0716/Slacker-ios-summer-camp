import SwiftUI

/// App shell: owns the prototype's shared store and the primary app navigation.
struct AppRootView: View {
    @State private var store = GroupBombModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var authSession = AuthSessionStore()
    @State private var tab = AppTab.groups
    @State private var tutorialStep: TutorialStep?
    @State private var createGroupTutorialWindowFrame: CGRect?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        SwiftUI.Group {
            if authSession.isCheckingSession {
                authenticationLoadingView
            } else if authSession.isAuthenticated, store.firebaseUID == authSession.currentUserID {
                authenticatedContent
                    .id(authSession.currentUserID)
            } else {
                AuthenticationView(session: authSession)
            }
        }
        .task {
            authSession.start { uid in store.changeCloudAccount(to: uid) }
            store.changeCloudAccount(to: authSession.currentUserID)
            if scenePhase == .active { store.resumeCloudSync() }
        }
        .onChange(of: authSession.currentUserID) { _, _ in
            if scenePhase == .active { store.resumeCloudSync() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resumeCloudSync() }
            else { store.suspendCloudSync() }
        }
        .onDisappear { store.suspendCloudSync() }
        .alert("雲端同步", isPresented: Binding(
            get: { store.cloudErrorMessage != nil },
            set: { if !$0 { store.cloudErrorMessage = nil } }
        )) {
            Button("重試") { Task { await store.reloadCloudGroups() } }
            Button("關閉", role: .cancel) { store.cloudErrorMessage = nil }
        } message: { Text(store.cloudErrorMessage ?? "") }
    }

    private var authenticatedContent: some View {
        ZStack {
            TabView(selection: $tab) {
                NavigationStack {
                    GroupListView(
                        model: store,
                        isSelected: tab == .groups,
                        tutorialStep: $tutorialStep,
                        onReplayTutorial: replayTutorial,
                        onCreateGroupTutorialFrameChange: {
                            createGroupTutorialWindowFrame = $0
                        }
                    )
                }
                .tabItem { Label(AppTab.groups.title, systemImage: AppTab.groups.symbol) }
                .tag(AppTab.groups)
                NavigationStack { MyTasksView(model: store) }
                    .tabItem { Label(AppTab.myTasks.title, systemImage: AppTab.myTasks.symbol) }
                    .tag(AppTab.myTasks)
                NavigationStack { SettingsView(model: store, authSession: authSession) }
                    .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
                    .tag(AppTab.settings)
            }
            .tint(BombTheme.ink)

        }
        .overlayPreferenceValue(TutorialTargetPreferenceKey.self) { targetAnchors in
            GeometryReader { proxy in
                if tutorialStep != nil {
                    OnboardingTutorialView(
                        step: $tutorialStep,
                        targets: tutorialFrames(from: targetAnchors, in: proxy),
                        onFinish: finishTutorial
                    )
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if !hasCompletedOnboarding, tutorialStep == nil {
                tab = .groups
                tutorialStep = .welcome
            }
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

    private func tutorialFrames(
        from targets: [TutorialTarget: Anchor<CGRect>],
        in proxy: GeometryProxy
    ) -> [TutorialTarget: CGRect] {
        let overlayFrame = proxy.frame(in: .global)
        var frames = targets.mapValues { proxy[$0] }

        if let createGroupTutorialWindowFrame {
            frames[.createGroupButton] = createGroupTutorialWindowFrame.offsetBy(
                dx: -overlayFrame.minX,
                dy: -overlayFrame.minY
            )
        }

        return frames
    }

    private func finishTutorial() {
        hasCompletedOnboarding = true
        tutorialStep = nil
    }

    private func replayTutorial() {
        hasCompletedOnboarding = false
        tab = .groups
        tutorialStep = .welcome
    }
}

#Preview { AppRootView() }
