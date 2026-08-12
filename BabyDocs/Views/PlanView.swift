import SwiftData
import SwiftUI

/// The home screen: what is left, soonest first.
///
/// Deliberately not a dashboard. The question a parent opens this app with is
/// "what do I have to do and when does it close", and every element here answers
/// some part of that. Anything that would be interesting but not actionable
/// belongs on the child hub.
struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]

    @State private var selectedChildID: UUID?
    @State private var showingDoneSection = false
    @State private var isEditingHousehold = false
    @State private var path: [UUID] = []
    @State private var family = FamilyService.shared
    @State private var navigator = AppNavigator.shared

    private var visibleChildren: [Child] {
        guard let selectedChildID else { return children }
        return children.filter { $0.id == selectedChildID }
    }

    private var tasks: [RequirementTask] {
        visibleChildren.flatMap(\.liveTasks)
    }

    /// Every task, whichever child is filtered in. A pushed detail and a
    /// notification route both have to resolve against the whole plan: a
    /// reminder that fires for the second baby must still open when the picker
    /// happens to be showing the first.
    private var allTasks: [RequirementTask] {
        children.flatMap(\.liveTasks)
    }

    private var overview: TaskPlanner.Overview {
        TaskPlanner.overview(for: tasks)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NextDeadlineCard(overview: overview)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    PlanProgressCard(overview: overview)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                if children.count > 1 {
                    Section {
                        Picker("Child", selection: $selectedChildID) {
                            Text("Everyone").tag(UUID?.none)
                            ForEach(children) { child in
                                Text(child.displayName).tag(UUID?.some(child.id))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                ForEach(openBuckets, id: \.bucket) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            TaskRow(task: task, showChildName: children.count > 1) {
                                toggle(task)
                            }
                        }
                    } header: {
                        Text(group.bucket.title)
                    } footer: {
                        if !group.bucket.blurb.isEmpty {
                            Text(group.bucket.blurb)
                        }
                    }
                }

                if doneTasks.isEmpty == false {
                    Section {
                        DisclosureGroup(isExpanded: $showingDoneSection) {
                            ForEach(doneTasks) { task in
                                TaskRow(task: task, showChildName: children.count > 1) {
                                    toggle(task)
                                }
                            }
                        } label: {
                            Text("Done and dismissed (\(doneTasks.count))")
                        }
                    }
                }

                if openBuckets.isEmpty && doneTasks.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "checklist",
                            title: "No plan yet",
                            message: "Finish the questions about your household and the plan builds itself.",
                            actionTitle: "Answer the questions",
                            action: { isEditingHousehold = true }
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Plan")
            .navigationDestination(for: UUID.self) { id in
                if let task = allTasks.first(where: { $0.id == id }) {
                    TaskDetailView(task: task)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            RequirementEngine.reconcileAll(in: context)
                        } label: {
                            Label("Rebuild the plan", systemImage: "arrow.clockwise")
                        }
                        if let child = visibleChildren.first {
                            SummaryShareControl {
                                PlanExporter.summary(
                                    for: child,
                                    profile: FamilyProfileStore.current(in: context)
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isEditingHousehold) {
                HouseholdEditorView()
            }
            .refreshable {
                await SyncCoordinator.shared.syncNow()
                RequirementEngine.reconcileAll(in: context)
            }
            // A reminder that opens the app on the plan list has spent the
            // parent's attention and given nothing back. The route is held until
            // the store has the row, so a cold launch lands on the task too.
            .onChange(of: navigator.pendingTaskID) { _, _ in openPendingTask() }
            // The row usually is not in the store yet on a cold launch: the
            // first reconciliation pass creates it a moment after this screen
            // appears, which is what this watches for.
            .onChange(of: allTasks.count) { _, _ in openPendingTask() }
            .task { openPendingTask() }
        }
    }

    private func openPendingTask() {
        guard let id = navigator.pendingTaskID else { return }
        guard allTasks.contains(where: { $0.id == id }) else { return }
        // The filter is cleared first: pushing a detail for a child the picker
        // has hidden would pop straight back off.
        selectedChildID = nil
        path = [id]
        navigator.pendingTaskID = nil
    }

    private var openBuckets: [(bucket: TaskPlanner.Bucket, tasks: [RequirementTask])] {
        TaskPlanner.buckets(for: tasks).filter { $0.bucket != .done }
    }

    private var doneTasks: [RequirementTask] {
        TaskPlanner.buckets(for: tasks).first { $0.bucket == .done }?.tasks ?? []
    }

    private func toggle(_ task: RequirementTask) {
        if task.isDone {
            task.completedAt = nil
            task.completedByName = ""
        } else {
            task.completedAt = Date()
            task.completedByName = family.selfDisplayName
        }
        task.recordLocalChange(in: context)
        Task {
            await DeadlineReminderScheduler.reschedule(for: children.flatMap(\.liveTasks))
        }
    }
}

#Preview {
    PlanView()
        .modelContainer(SampleData.previewContainer())
}
