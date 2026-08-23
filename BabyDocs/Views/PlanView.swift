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
    @State private var isSharingPlan = false
    @State private var path: [UUID] = []
    @State private var navigator = AppNavigator.shared

    private var visibleChildren: [Child] {
        guard let selectedChildID else { return children }
        return children.filter { $0.id == selectedChildID }
    }

    /// Sharing and exporting are one-child operations. Never let the combined
    /// view silently choose the first child, which is especially dangerous for
    /// twins who share a birth date and state.
    private var shareableChild: Child? {
        if children.count == 1 { return children.first }
        guard let selectedChildID else { return nil }
        return children.first { $0.id == selectedChildID }
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

    /// Sent, overdue back, and nobody has told the family. Hoisted to the top of
    /// the screen because it is the one thing here that a parent could not have
    /// worked out from their own calendar.
    private var lateTasks: [RequirementTask] {
        tasks.filter { $0.isLate() }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    PlanHeaderCard(overview: overview)
                        .planCardRow()
                }

                Section {
                    Button {
                        isEditingHousehold = true
                    } label: {
                        HStack(alignment: .top, spacing: AppTheme.spacing) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                                Text("Change household answers")
                                    .font(.subheadline.weight(.semibold))
                                Text("Update the answers that shape every deadline in this plan.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .planCard(padding: AppTheme.spacing)
                    }
                    .pressableCard()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Change household answers")
                    .accessibilityHint("Opens the household answers used to build every child's plan")
                    .planCardRow()
                }

                if !lateTasks.isEmpty {
                    Section {
                        ForEach(lateTasks) { task in
                            TaskRow(task: task, showChildName: children.count > 1) {
                                toggle(task)
                            }
                        }
                    } header: {
                        PlanSectionHeader(
                            title: "Sent, and still not here",
                            blurb: "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top.",
                            count: lateTasks.count
                        )
                    }
                }

                if children.count > 1 {
                    Section {
                    Picker("Child", selection: $selectedChildID) {
                            Text("Everyone").tag(UUID?.none)
                            ForEach(children) { child in
                                Text(child.displayName).tag(UUID?.some(child.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: 0, leading: AppTheme.margin, bottom: AppTheme.tightSpacing, trailing: AppTheme.margin
                    ))
                    if selectedChildID == nil {
                        Text("Choose one child before sending or exporting a plan.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Color.clear)
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
                        PlanSectionHeader(
                            title: group.bucket.title,
                            blurb: group.bucket.blurb,
                            // What is *left* here, not how many rows are drawn.
                            // The ticked ones stay on screen, and a count that
                            // includes them turns the one number on the header
                            // into a number nobody can act on.
                            count: group.tasks.filter { !$0.isDone }.count
                        )
                    }
                }

                if dismissedTasks.isEmpty == false {
                    Section {
                        DisclosureGroup(isExpanded: $showingDoneSection) {
                            ForEach(dismissedTasks) { task in
                                TaskRow(task: task, showChildName: children.count > 1) {
                                    toggle(task)
                                }
                            }
                        } label: {
                            Text("Does not apply to us (\(dismissedTasks.count))")
                        }
                    }
                }

                if openBuckets.isEmpty && dismissedTasks.isEmpty {
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
            .listStyle(.insetGrouped)
            .planPageBackground()
            .navigationTitle("Plan")
            .navigationDestination(for: UUID.self) { id in
                if let task = allTasks.first(where: { $0.id == id }) {
                    TaskDetailView(task: task)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isEditingHousehold = true
                    } label: {
                        Label("Change household answers", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Change household answers")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let child = shareableChild {
                            Button {
                                isSharingPlan = true
                            } label: {
                                Label("Send this plan to the other parent", systemImage: "paperplane")
                            }
                            SummaryShareControl {
                                PlanExporter.summary(
                                    for: child,
                                    profile: FamilyProfileStore.current(in: context)
                                )
                            }
                        } else {
                            Label("Choose one child before sharing", systemImage: "person.crop.circle.badge.questionmark")
                        }
                        Divider()
                        Button {
                            RequirementEngine.reconcileAll(in: context)
                            Task {
                                await DeadlineReminderScheduler.reschedule(in: context)
                            }
                        } label: {
                            Label("Rebuild the plan", systemImage: "arrow.clockwise")
                        }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Plan options")
                .accessibilityHint("More actions for this plan")
            }
            }
            .sheet(isPresented: $isEditingHousehold) {
                HouseholdEditorView()
            }
            .sheet(isPresented: $isSharingPlan) {
                if let child = shareableChild {
                    SharePlanSheet(child: child)
                }
            }
            .onChange(of: children.map { $0.id }) { _, _ in
                normalizeSelection()
            }
            .task {
                normalizeSelection()
            }
            .refreshable {
                RequirementEngine.reconcileAll(in: context)
                await DeadlineReminderScheduler.reschedule(in: context)
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

    private func normalizeSelection() {
        guard let selectedChildID else {
            if children.count == 1 {
                self.selectedChildID = children.first?.id
            }
            return
        }
        guard children.contains(where: { $0.id == selectedChildID }) else {
            self.selectedChildID = children.count == 1 ? children.first?.id : nil
            return
        }
    }

    /// **A ticked task stays where it was.**
    ///
    /// It used to drop out of its section and into a collapsed disclosure at
    /// the bottom of the screen, which makes ticking a row indistinguishable
    /// from deleting it: the row the parent just dealt with vanishes from the
    /// only place they would look for it. Struck through and dimmed, in place,
    /// answers both of the questions actually being asked at a records-office
    /// counter, which are "what is left" and "did I already do this one".
    private var openBuckets: [(bucket: TaskPlanner.Bucket, tasks: [RequirementTask])] {
        let late = Set(lateTasks.map(\.id))
        return TaskPlanner.buckets(for: tasks, completed: .inPlace)
            .filter { $0.bucket != .done }
            .map { (bucket: $0.bucket, tasks: $0.tasks.filter { !late.contains($0.id) }) }
            .filter { !$0.tasks.isEmpty }
    }

    /// Only the ones a parent said do not apply to them. Those are a statement
    /// about the rule rather than about the work, so they do leave the plan.
    private var dismissedTasks: [RequirementTask] {
        TaskPlanner.sorted(tasks.filter { $0.isDismissed })
    }

    private func toggle(_ task: RequirementTask) {
        let wasDone = task.isDone
        task.setCompleted(!wasDone)
        let saved = task.recordLocalChange(in: context)
        if saved && !wasDone {
            ReviewPromptTracker.recordCompletion(of: task)
        }
        if saved {
            Task {
                await DeadlineReminderScheduler.reschedule(for: children.flatMap(\.liveTasks))
            }
        }
    }
}

#Preview {
    PlanView()
        .modelContainer(SampleData.previewContainer())
}
