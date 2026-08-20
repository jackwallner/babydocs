import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }) private var children: [Child]
    @Query(filter: #Predicate<Child> { $0.deletedAt != nil }, sort: \Child.birthDate)
    private var archivedChildren: [Child]

    @State private var navigator = AppNavigator.shared
    @State private var saveFailures = SaveFailureReporter.shared
    /// One ask per launch at most, whatever else happens.
    @State private var hasRequestedReviewThisSession = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Group {
            if children.isEmpty && archivedChildren.isEmpty {
                // No child means no plan, and a plan is the entire app. The
                // intake is not a wizard the user can be dropped into the
                // middle of: every deadline in the app is derived from the
                // birth date and the state, so there is nothing to show until
                // those exist.
                OnboardingFlow()
            } else if children.isEmpty {
                ArchivedChildrenRecoveryView(children: archivedChildren)
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
                // **Nothing is set on the tab bar on purpose.**
                //
                // It used to be forced visible and painted with the page
                // colour, which turns the system's floating glass capsule into
                // an opaque grey slab: the page then shows through as two black
                // gutters either side of it, which is the "black bars" in the
                // screenshots. Left alone, the bar is Liquid Glass, it takes its
                // own material from whatever scrolls under it, and there are no
                // gutters because there is no slab. `planPageBackground()` on
                // each tab is what gives the glass something to refract.
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
        // A local-only app that swallows a failed write is telling the parent
        // their work is safe when it is not. This is the one place that says so,
        // wherever the write happened.
        .alert("That did not save", isPresented: saveFailureBinding) {
            Button("OK", role: .cancel) { saveFailures.clear() }
        } message: {
            Text(saveFailures.message ?? "")
        }
        .alert("That link did not work", isPresented: $navigator.seedFailed) {
            Button("OK", role: .cancel) { navigator.seedFailed = false }
        } message: {
            Text("Some message apps break long links. Ask the other parent to send it again, or answer the questions yourself: it takes about a minute.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .babyDocsDeadlineMet)) { _ in
            scheduleReviewRequestAfterDeadlineMet()
        }
        .task(id: children.count) {
            // Runs the catalog against whatever is in the store, at launch and
            // whenever a child is added. Cheap when nothing changed: the engine
            // writes only what actually moved.
            RequirementEngine.reconcileAll(in: context)
            await DeadlineReminderScheduler.reschedule(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                RequirementEngine.reconcileAll(in: context)
                Task {
                    await StoreService.shared.refresh()
                    await DeadlineReminderScheduler.reschedule(in: context)
                }
            case .inactive, .background:
                // Handing the phone to someone between two appointments should
                // not hand them the document vault as well.
                VaultStore.shared.lock()
            default:
                break
            }
        }
    }

    /// The system ask, one beat after the tick.
    ///
    /// `requestReview()` and nothing in front of it: no question about whether
    /// the app is helping, and no branch that decides who is allowed to reach
    /// the store. All this decides is the moment, which is the one thing the
    /// system API cannot know.
    ///
    /// Delayed rather than immediate because the row animates out of its bucket
    /// and into Done, and a sheet that lands on top of that reads as a
    /// consequence of the tap. Held back entirely while the paywall or an
    /// incoming plan link is on screen: those are the two places where an
    /// interruption costs something.
    private func scheduleReviewRequestAfterDeadlineMet() {
        guard eligibleToRequestReview else { return }

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard eligibleToRequestReview else { return }
            hasRequestedReviewThisSession = true
            ReviewPromptTracker.markRequested()
            requestReview()
        }
    }

    private var saveFailureBinding: Binding<Bool> {
        Binding(
            get: { saveFailures.message != nil },
            set: { if !$0 { saveFailures.clear() } }
        )
    }

    private var eligibleToRequestReview: Bool {
        !hasRequestedReviewThisSession
            && !navigator.isShowingPaywall
            && navigator.pendingSeed == nil
            && ReviewPromptTracker.shouldRequestAfterPositiveMoment()
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
