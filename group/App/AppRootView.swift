import SwiftUI

/// App shell: owns the prototype's shared store and the primary app navigation.
struct AppRootView: View {
    @State private var store = GroupBombModel()
    @State private var tab = AppTab.groups
    @State private var tutorialStep: TutorialStep?
    @State private var tutorialTargets: [TutorialTarget: CGRect] = [:]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                NavigationStack {
                    GroupListView(
                        model: store,
                        tutorialStep: $tutorialStep,
                        onReplayTutorial: replayTutorial
                    )
                }
                .tabItem { Label(AppTab.groups.title, systemImage: AppTab.groups.symbol) }
                .tag(AppTab.groups)
                NavigationStack { MyTasksView(model: store) }
                    .tabItem { Label(AppTab.myTasks.title, systemImage: AppTab.myTasks.symbol) }
                    .tag(AppTab.myTasks)
                NavigationStack { SettingsView(model: store) }
                    .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.symbol) }
                    .tag(AppTab.settings)
            }
            .tint(BombTheme.ink)

            if tutorialStep != nil {
                OnboardingTutorialView(
                    step: $tutorialStep,
                    targets: tutorialTargets,
                    onFinish: finishTutorial
                )
            }
        }
        .onPreferenceChange(TutorialTargetPreferenceKey.self) { tutorialTargets = $0 }
        .onAppear {
            if !hasCompletedOnboarding, tutorialStep == nil {
                tab = .groups
                tutorialStep = .welcome
            }
        }
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
