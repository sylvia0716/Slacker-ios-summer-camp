import SwiftUI

/// App shell: owns the prototype's shared store and the primary app navigation.
struct AppRootView: View {
    @State private var store = GroupBombModel()
    @State private var authSession = AuthSessionStore()
    @State private var tab = AppTab.groups
    @State private var tutorialStep: TutorialStep?
    @State private var createGroupTutorialWindowFrame: CGRect?

    var body: some View {
        SwiftUI.Group {
            if authSession.isCheckingSession {
                authenticationLoadingView
            } else if authSession.isAuthenticated {
                authenticatedContent
            } else {
                AuthenticationView(session: authSession)
            }
        }
        .task { authSession.start() }
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
                NavigationStack {
                    SettingsView(
                        model: store,
                        authSession: authSession,
                        onReplayTutorial: replayTutorial
                    )
                }
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
