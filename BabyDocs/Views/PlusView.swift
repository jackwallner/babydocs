import SwiftData
import SwiftUI

/// The Plus tab: the offer while it is an offer, the tools once it is not.
///
/// A tab rather than a sheet, because the old arrangement could only ever show
/// the pitch as a refusal. It is the same slot in the bar either way, which is
/// the point: a customer who has paid should not watch a fifth of their tab bar
/// keep advertising something they already own, and the timeline is the part of
/// Plus that wants a screen of its own anyway.
struct PlusView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]

    @State private var store = StoreService.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.isPro {
                    PlusToolsView(children: children)
                } else {
                    PlusPurchaseView(placement: .tab)
                }
            }
            .navigationTitle("Baby Docs Plus")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - The tools

/// What Plus actually is, once it is bought: the order to do things in, what
/// gets said out loud and when, and the pages that leave the phone.
struct PlusToolsView: View {
    @Environment(\.modelContext) private var context
    let children: [Child]

    @State private var selectedChildID: UUID?
    @State private var notifications = NotificationService.shared
    @State private var preferences = ReminderPreferences.shared
    @State private var store = StoreService.shared
    @State private var calendarFile: URL?
    @State private var errorMessage: String?

    private var child: Child? {
        if let selectedChildID { return children.first { $0.id == selectedChildID } }
        return children.first
    }

    private var tasks: [RequirementTask] {
        child?.liveTasks ?? []
    }

    var body: some View {
        List {
            if children.count > 1 {
                Section {
                    Picker("Child", selection: $selectedChildID) {
                        ForEach(children) { child in
                            Text(child.displayName).tag(UUID?.some(child.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            timelineSections

            Section {
                Toggle("Suggested dates", isOn: Binding(
                    get: { preferences.suggestedDateReminders },
                    set: { preferences.setSuggestedDateReminders($0); rescheduleReminders() }
                ))
                Toggle("This week's paperwork, on Sundays", isOn: Binding(
                    get: { preferences.weeklyDigest },
                    set: { preferences.setWeeklyDigest($0); rescheduleReminders() }
                ))
                if notifications.authorizationStatus == .notDetermined {
                    Button("Turn on notifications") {
                        Task {
                            await notifications.requestAuthorization()
                            await DeadlineReminderScheduler.reschedule(in: context)
                        }
                    }
                } else if notifications.authorizationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("What gets said out loud")
            } footer: {
                Text("The two windows that legally close are always announced, for everybody, whatever is switched off here. These are the rest: the dates Baby Docs suggests, three days out, and one Sunday message about the week ahead that stays silent on a week with nothing in it. Any single task can also carry a reminder you set yourself.")
            }

            Section {
                if let child {
                    if let calendarFile {
                        ShareLink(item: calendarFile) {
                            Label("Put the dates in a calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                    SummaryShareControl(
                        summary: {
                            PlanExporter.summary(
                                for: child,
                                profile: FamilyProfileStore.current(in: context)
                            )
                        }
                    )
                    if FamilyProfileStore.current(in: context).insuranceKind == .employer {
                        SummaryShareControl(
                            summary: {
                                PlanExporter.employerPacket(
                                    for: child,
                                    profile: FamilyProfileStore.current(in: context)
                                )
                            },
                            title: "Employer packet",
                            symbol: "briefcase"
                        )
                    }
                }
            } header: {
                Text("Pages that leave the phone")
            } footer: {
                Text("The calendar file carries the dates, why each one exists and the official link, and nothing else: no notes, no confirmation numbers, and nothing at all from the document vault. Import it and the deadlines sit beside the appointments they are competing with, where the other parent can see them too.")
            }

            Section {
                Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Button("Restore purchases") { restore() }
            } footer: {
                Text("Anything already in the document vault stays readable if a subscription lapses. Lapsing stops you adding more; it never takes back what is there.")
            }
        }
        .listStyle(.insetGrouped)
        .planPageBackground()
        // Rebuilt whenever this screen is shown or the child changes, so the
        // share sheet can never hand somebody a file describing last week's
        // plan. It is a few lines of text into the temporary directory.
        .task(id: child?.id) {
            // The picker has to start on the child the rest of the screen is
            // already showing, or a family with twins opens on a blank menu
            // above a timeline that clearly belongs to somebody.
            if selectedChildID == nil { selectedChildID = children.first?.id }
            guard let child else { return }
            makeCalendarFile(for: child)
        }
        .onChange(of: children.map { $0.id }) { _, _ in
            normalizeSelection()
        }
        .task {
            normalizeSelection()
        }
        .navigationDestination(for: UUID.self) { id in
            if let task = children.flatMap(\.liveTasks).first(where: { $0.id == id }) {
                TaskDetailView(task: task)
            }
        }
        .alert("Calendar", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Timeline

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

    @ViewBuilder
    private var timelineSections: some View {
        let groups = PlanTimeline.groups(for: tasks)
        if groups.isEmpty {
            Section {
                Text("Nothing on the plan yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(groups, id: \.phase) { group in
                Section {
                    ForEach(group.steps) { step in
                        TimelineRow(step: step)
                    }
                } header: {
                    PlanSectionHeader(
                        title: group.phase.title,
                        blurb: group.phase.blurb,
                        count: group.steps.filter { !$0.isDone }.count
                    )
                }
            }
        }
    }

    private func makeCalendarFile(for child: Child) {
        do {
            let text = CalendarExporter.ics(for: child)
            calendarFile = try CalendarExporter.write(text, named: "baby-docs-\(child.displayName)")
        } catch {
            errorMessage = "The calendar file could not be written. Try again after freeing some space."
        }
    }

    private func rescheduleReminders() {
        Task { await DeadlineReminderScheduler.reschedule(in: context) }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func restore() {
        Task {
            do {
                switch try await store.restore() {
                case .restored:
                    Haptics.purchased()
                case .nothingToRestore:
                    errorMessage = "No previous purchase was found for this Apple Account."
                case .unavailable:
                    errorMessage = "Purchases cannot be restored in this build."
                }
            } catch {
                errorMessage = "Purchases could not be restored right now. Check your Apple Account and try again."
            }
        }
    }
}

/// One task on the timeline, with the reason it sits where it does.
///
/// The reason is the whole feature. A list of tasks in a different order is a
/// rearrangement; a list that says "this is waiting on the certified copy" is
/// the thing a parent could not work out themselves at three in the morning.
struct TimelineRow: View {
    let step: PlanTimeline.Step

    var body: some View {
        NavigationLink(value: step.taskID) {
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(step.title)
                    .font(.body)
                    .foregroundStyle(step.isDone ? .secondary : .primary)
                    .strikethrough(step.isDone, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !step.reason.isEmpty {
                    HStack(alignment: .top, spacing: AppTheme.hairSpacing) {
                        Image(systemName: step.isBlocked ? "hourglass" : "arrow.turn.down.right")
                            .font(.caption2)
                        Text(step.reason)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue(step.reason)
        .accessibilityHint("Opens task details")
    }
}

#Preview {
    PlusView()
        .modelContainer(SampleData.previewContainer())
}
