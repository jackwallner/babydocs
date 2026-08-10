import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }) private var children: [Child]

    @State private var navigator = AppNavigator.shared
    @State private var store = StoreService.shared
    @State private var sync = SyncCoordinator.shared

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

                    FamilyView()
                        .tabItem { Label("Family", systemImage: "person.2.fill") }
                        .tag(AppNavigator.Tab.family)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppNavigator.Tab.settings)
                }
            }
        }
        .sheet(isPresented: $navigator.isShowingPaywall) {
            PaywallView()
        }
        .task(id: children.count) {
            // Runs the catalog against whatever is in the store, at launch and
            // whenever a child is added. Cheap when nothing changed: the engine
            // writes only what actually moved.
            RequirementEngine.reconcileAll(in: context)
            await rescheduleReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await SyncCoordinator.shared.syncNow()
                RequirementEngine.reconcileAll(in: context)
                await rescheduleReminders()
            }
        }
        .onChange(of: navigator.pendingInviteCode) { _, code in
            // An invitation can land at any moment, including mid-intake. It
            // always wins the Family tab rather than interrupting whatever is
            // on screen.
            guard code != nil, !children.isEmpty else { return }
            navigator.selectedTab = .family
        }
    }

    private func rescheduleReminders() async {
        let tasks = children.flatMap(\.liveTasks)
        await DeadlineReminderScheduler.reschedule(for: tasks)
    }
}

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
}
