import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }) private var children: [Child]

    @State private var navigator = AppNavigator.shared
    @State private var reviewCoordinator = ReviewPromptCoordinator.shared
    @State private var isShowingReviewPrompt = false
    @State private var reviewPromptStep: ReviewPromptSheet.Step = .enjoyment
    /// One ask per launch at most, whatever else happens.
    @State private var hasShownReviewPromptThisSession = false
    @State private var shouldRequestNativeReviewOnDismiss = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Group {
            if children.isEmpty {
                // No child means no plan, and a plan is the entire app. The
                // intake is not a wizard the user can be dropped into the
                // middle of: every deadline in the app is derived from the
                // birth date and the state, so there is nothing to show until
                // those exist.
                OnboardingFlow()
            } else {
                TabView(selection: $navigator.selectedTab) {
                    PlanView()
                        .tabItem { Label("Plan", systemImage: "checklist") }
                        .tag(AppNavigator.Tab.plan)

                    ChildrenView()
                        .tabItem { Label("Children", systemImage: "figure.and.child.holdinghands") }
                        .tag(AppNavigator.Tab.children)

                    DocumentsView()
                        .tabItem { Label("Documents", systemImage: "folder") }
                        .tag(AppNavigator.Tab.documents)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppNavigator.Tab.settings)
                }
                // Lets the plan scroll under the floating tab bar instead of
                // stopping at a hard edge with black either side of the glass.
                // Paired with `planPageBackground()` on each tab, which gives
                // the blur something to actually blur.
                .toolbarBackground(.hidden, for: .tabBar)
            }
        }
        .sheet(isPresented: $navigator.isShowingPaywall) {
            PaywallView()
        }
        .sheet(item: $navigator.pendingSeed) { seed in
            ImportPlanSheet(seed: seed) {
                navigator.selectedTab = .plan
            }
        }
        .alert("That link did not work", isPresented: $navigator.seedFailed) {
            Button("OK", role: .cancel) { navigator.seedFailed = false }
        } message: {
            Text("Some message apps break long links. Ask the other parent to send it again, or answer the questions yourself: it takes about a minute.")
        }
        .sheet(isPresented: $isShowingReviewPrompt, onDismiss: {
            if shouldRequestNativeReviewOnDismiss {
                shouldRequestNativeReviewOnDismiss = false
                requestReview()
            } else if !ReviewPromptTracker.isSoftDeferred {
                // Swiped away rather than answered. Still counts as an ask, but
                // only the long cooldown applies when the tracker is not already
                // holding the short one.
                ReviewPromptTracker.markShown()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptStep) { outcome in
                isShowingReviewPrompt = false
                if case .enjoyedMaybeLater = outcome {
                    shouldRequestNativeReviewOnDismiss = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .babyDocsDeadlineMet)) { _ in
            scheduleReviewPromptAfterDeadlineMet()
        }
        // Settings can open the funnel directly, which skips eligibility: asking
        // to be asked is its own qualification.
        .onChange(of: reviewCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewCoordinator.clear() }
            guard !isShowingReviewPrompt else { return }
            switch presentation {
            case .enjoymentPrompt: present(reviewStep: .enjoyment)
            case .feedbackOnly: present(reviewStep: .feedback)
            }
        }
        .task(id: children.count) {
            // Runs the catalog against whatever is in the store, at launch and
            // whenever a child is added. Cheap when nothing changed: the engine
            // writes only what actually moved.
            RequirementEngine.reconcileAll(in: context)
            await rescheduleReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                RequirementEngine.reconcileAll(in: context)
                Task { await rescheduleReminders() }
            case .background:
                // Handing the phone to someone between two appointments should
                // not hand them the document vault as well.
                VaultStore.shared.lock()
            default:
                break
            }
        }
    }

    /// The ask, one beat after the tick.
    ///
    /// Delayed rather than immediate because the row animates out of its bucket
    /// and into Done, and a sheet that lands on top of that reads as a
    /// consequence of the tap rather than a question. Held back entirely while
    /// the paywall or an incoming plan link is on screen: those are the two
    /// places where an interruption costs something.
    private func scheduleReviewPromptAfterDeadlineMet() {
        guard !hasShownReviewPromptThisSession,
              !isShowingReviewPrompt,
              !navigator.isShowingPaywall,
              navigator.pendingSeed == nil,
              ReviewPromptTracker.shouldShowAfterPositiveMoment() else { return }

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !hasShownReviewPromptThisSession,
                  !isShowingReviewPrompt,
                  !navigator.isShowingPaywall,
                  navigator.pendingSeed == nil,
                  ReviewPromptTracker.shouldShowAfterPositiveMoment() else { return }
            ReviewPromptTracker.consumePendingPositiveMoment()
            present(reviewStep: .enjoyment)
        }
    }

    private func present(reviewStep step: ReviewPromptSheet.Step) {
        reviewPromptStep = step
        hasShownReviewPromptThisSession = true
        isShowingReviewPrompt = true
    }

    private func rescheduleReminders() async {
        let tasks = children.flatMap(\.liveTasks)
        await DeadlineReminderScheduler.reschedule(for: tasks)
    }
}

/// `sheet(item:)` needs an identity, and a seed's identity is its contents: two
/// taps on the same link are the same sheet, and a different link is a different
/// one.
extension PlanSeed: Identifiable {
    var id: String { encoded() ?? "\(birthDate.timeIntervalSince1970)" }
}

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
}
