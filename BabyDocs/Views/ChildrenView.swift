import SwiftData
import SwiftUI

struct ChildrenView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]
    @Query(filter: #Predicate<Child> { $0.deletedAt != nil }, sort: \Child.birthDate)
    private var archivedChildren: [Child]

    @State private var editingChild: Child?
    /// The child "Add another child" just made, until Done confirms it. See
    /// `addChild()`.
    @State private var draftChildID: UUID?
    @State private var isEditingHousehold = false
    @State private var store = StoreService.shared
    @State private var navigator = AppNavigator.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(children) { child in
                        NavigationLink(value: child.id) {
                            ChildRow(child: child)
                        }
                    }
                }

                if !restorableArchivedChildren.isEmpty {
                    Section {
                        ForEach(restorableArchivedChildren) { child in
                            Button {
                                restore(child)
                            } label: {
                                HStack {
                                    ChildRow(child: child)
                                    Spacer(minLength: AppTheme.tightSpacing)
                                    Image(systemName: "arrow.uturn.backward")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .pressableCard()
                            .accessibilityLabel("Restore \(child.displayName)")
                            .accessibilityHint("Puts this child back in the plan")
                        }
                    } header: {
                        Text("Archived children")
                    } footer: {
                        Text("Archived children keep their plan and receipts. Restore one if it was removed by mistake.")
                    }
                }

                Section {
                    Button {
                        addChild()
                    } label: {
                        Label("Add another child", systemImage: "plus")
                    }
                } footer: {
                    if !store.isPro {
                        Text("The first baby is free, with every deadline, link and document list. Plus covers any further children.")
                    }
                }

                Section {
                    Button {
                        isEditingHousehold = true
                    } label: {
                        Label("Household answers", systemImage: "house")
                    }
                } footer: {
                    Text("Where you live, how you are covered, whether you are taking leave. Changing an answer here rebuilds every child's plan.")
                }
            }
            .listStyle(.insetGrouped)
            .planPageBackground()
            .navigationTitle("Children")
            .navigationDestination(for: UUID.self) { id in
                if let child = children.first(where: { $0.id == id }) {
                    ChildDetailView(child: child)
                }
            }
            .sheet(item: $editingChild, onDismiss: discardUnconfirmedDraft) { child in
                ChildEditorSheet(
                    child: child,
                    isDraft: child.id == draftChildID,
                    onConfirm: { draftChildID = nil }
                )
            }
            .sheet(isPresented: $isEditingHousehold) {
                HouseholdEditorView()
            }
        }
    }

    /// A draft, not a child, until Done says so.
    ///
    /// The sheet needs a real row to bind to, so one is inserted, but it is
    /// inserted **tombstoned**: every list, every query and the requirement
    /// engine skip `deletedAt != nil`, so nothing sees it and no plan is built
    /// from it. Done clears the tombstone; anything else, including a swipe
    /// down, removes the row outright.
    ///
    /// It shipped as a plain insert, which meant swiping the sheet away left a
    /// child called nothing, born today, with a birth state inherited from the
    /// household, and a full generated plan hanging off it. Every one of those
    /// values was the app's guess presented as the family's answer.
    ///
    /// The birth state is deliberately not inherited any more either. It is
    /// right most of the time and it is silent, and the times it is wrong are a
    /// parent sent to the wrong state's vital records office for a fortnight.
    private func addChild() {
        guard store.isPro || children.isEmpty else {
            navigator.requestUpgrade()
            return
        }
        let child = Child(birthDate: Date())
        child.colorIndex = children.count
        child.deletedAt = Date()
        context.insert(child)
        draftChildID = child.id
        child.recordLocalChange(in: context)
        editingChild = child
    }

    /// Runs whenever the editor closes. A draft that was never confirmed is
    /// removed for real: it is scaffolding the app put there, not work the
    /// family did, so there is nothing a tombstone would be protecting.
    private func discardUnconfirmedDraft() {
        guard let id = draftChildID else { return }
        draftChildID = nil
        var descriptor = FetchDescriptor<Child>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let draft = (try? context.fetch(descriptor))?.first else { return }
        draft.discardEphemeral(in: context)
    }

    private var restorableArchivedChildren: [Child] {
        archivedChildren.filter { $0.id != draftChildID }
    }

    private func restore(_ child: Child) {
        child.deletedAt = nil
        child.recordLocalChange(in: context)
        RequirementEngine.reconcile(
            child: child,
            profile: FamilyProfileStore.current(in: context),
            in: context
        )
        Task {
            await DeadlineReminderScheduler.reschedule(in: context)
        }
        AppNavigator.shared.selectedTab = .plan
    }
}

struct ArchivedChildrenRecoveryView: View {
    @Environment(\.modelContext) private var context
    let children: [Child]
    @State private var isStartingOver = false

    var body: some View {
        if isStartingOver {
            OnboardingFlow()
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.looseSpacing) {
                        Text("This child is archived")
                            .font(.title2.weight(.semibold))

                        Text("The plan and any receipts are still on this phone. Restore the child to reopen the plan, or start with a new child while keeping this archive.")
                            .foregroundStyle(.secondary)

                        ForEach(children) { child in
                            Button {
                                restore(child)
                            } label: {
                                HStack {
                                    ChildRow(child: child)
                                    Spacer(minLength: AppTheme.tightSpacing)
                                    Image(systemName: "arrow.uturn.backward")
                                        .foregroundStyle(.tint)
                                }
                                .padding(AppTheme.spacing)
                                .background(AppTheme.surface, in: AppTheme.cardShape)
                            }
                            .pressableCard()
                            .accessibilityLabel("Restore \(child.displayName)")
                            .accessibilityHint("Puts this child back in the plan")
                        }

                        Button("Start with a new child") {
                            isStartingOver = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Keeps the archived child and opens the questions for a new plan")

                        Text("Archiving changes only this phone. No household data is uploaded by archiving, and the child stays available until you restore them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppTheme.margin)
                }
                .background(AppTheme.pageBackground)
                .navigationTitle("Baby Docs")
            }
        }
    }

    private func restore(_ child: Child) {
        child.deletedAt = nil
        child.recordLocalChange(in: context)
        RequirementEngine.reconcile(
            child: child,
            profile: FamilyProfileStore.current(in: context),
            in: context
        )
        Task {
            await DeadlineReminderScheduler.reschedule(in: context)
        }
        AppNavigator.shared.selectedTab = .plan
    }
}

private struct ChildRow: View {
    let child: Child

    var body: some View {
        let overview = TaskPlanner.overview(for: child.liveTasks)
        HStack(spacing: AppTheme.spacing) {
            ZStack {
                Circle().fill(child.color.opacity(0.18))
                Text(child.initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(child.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(child.displayName).font(.body)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            // A bare number in the corner of a row is a badge nobody can read:
            // eighteen of what, and is more of it better or worse.
            Text("\(overview.openCount) left")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(overview.overdueCount > 0 ? .red : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            overview.overdueCount > 0
                ? "\(overview.openCount) open tasks, \(overview.overdueCount) overdue"
                : "\(overview.openCount) open tasks"
        )
    }

    private var summary: String {
        let age = child.ageInDays
        let ageText = age < 0 ? "due soon" : "\(age) days old"
        let place = child.birthStateCode.isEmpty
            ? ""
            : ", born in \(USState.displayName(for: child.birthStateCode))"
        return ageText + place
    }
}

// MARK: - Child detail

struct ChildDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var child: Child
    @State private var isEditing = false
    @State private var isSharing = false

    var body: some View {
        List {
            Section {
                let overview = TaskPlanner.overview(for: child.liveTasks)
                PlanProgressCard(overview: overview)
                    .planCardRow()
            }

            Section {
                Picker("Social Security", selection: ssnBinding) {
                    ForEach(SSNStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                Toggle("Certified birth certificate in hand", isOn: certificateBinding)
                if child.birthCertificateReceivedAt != nil {
                    Stepper(
                        "Certified copies: \(child.certifiedCopiesOnHand)",
                        value: copiesBinding,
                        in: 0...10
                    )
                }
            } header: {
                Text("Documents")
            } footer: {
                Text("These two answers open and close tasks. Marking the certificate in hand unblocks the passport task and adds the check for a misspelled name.")
            }

            Section("Details") {
                LabeledContent("Born", value: child.birthDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Registered in", value: birthPlace)
                Button("Edit details") { isEditing = true }
            }

            Section {
                Button {
                    isSharing = true
                } label: {
                    Label("Send or print this plan", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("The link for the other parent, the printable one-pager and the employer packet.")
            }
        }
        .listStyle(.insetGrouped)
        .planPageBackground()
        .navigationTitle(child.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            ChildEditorSheet(child: child)
        }
        .sheet(isPresented: $isSharing) {
            SharePlanSheet(child: child)
        }
    }

    private var birthPlace: String {
        var parts: [String] = []
        if !child.birthCounty.isEmpty { parts.append(child.birthCounty) }
        if !child.birthStateCode.isEmpty { parts.append(USState.displayName(for: child.birthStateCode)) }
        return parts.isEmpty ? "Not set" : parts.joined(separator: ", ")
    }

    private var ssnBinding: Binding<SSNStatus> {
        Binding(
            get: { child.ssnStatus },
            set: { newValue in
                child.ssnStatus = newValue
                child.ssnReceivedAt = newValue == .cardReceived ? (child.ssnReceivedAt ?? Date()) : nil
                child.recordLocalChange(in: context)
                rebuild()
            }
        )
    }

    private var certificateBinding: Binding<Bool> {
        Binding(
            get: { child.birthCertificateReceivedAt != nil },
            set: { newValue in
                child.birthCertificateReceivedAt = newValue ? Date() : nil
                if !newValue { child.certifiedCopiesOnHand = 0 }
                child.recordLocalChange(in: context)
                rebuild()
            }
        )
    }

    private var copiesBinding: Binding<Int> {
        Binding(
            get: { child.certifiedCopiesOnHand },
            set: { newValue in
                child.certifiedCopiesOnHand = newValue
                child.recordLocalChange(in: context)
            }
        )
    }

    private func rebuild() {
        RequirementEngine.reconcile(
            child: child,
            profile: FamilyProfileStore.current(in: context),
            in: context
        )
        Task {
            await DeadlineReminderScheduler.reschedule(in: context)
        }
    }
}

// MARK: - Editor

struct ChildEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var child: Child
    /// True while this row is an unconfirmed draft from "Add another child".
    /// See `ChildrenView.addChild()`.
    var isDraft = false
    var onConfirm: (() -> Void)?
    @State private var originalBirthStateCode: String?

    /// The two answers every deadline in the app is derived from. A plan built
    /// on today's date and a blank state is not a weaker plan, it is a wrong
    /// one, so Done does not accept it.
    private var canSave: Bool {
        !child.birthStateCode.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    TextField("First name", text: $child.name)
                    DatePicker(
                        "Date of birth",
                        selection: $child.birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                Section {
                    Picker("State of birth", selection: $child.birthStateCode) {
                        Text("Select").tag("")
                        ForEach(USState.all) { state in
                            Text(state.name).tag(state.code)
                        }
                    }
                    CountyField(stateCode: child.birthStateCode, county: $child.birthCounty)
                    Toggle("US citizen", isOn: $child.isUSCitizen)
                } footer: {
                    let office = StateVitalRecords.office(for: child.birthStateCode)
                    if child.birthStateCode.isEmpty {
                        Text("Where this birth was registered, which is not always where you live now. Every date and every office in this child's plan comes from it, so there is no sensible default and Baby Docs will not pick one for you.")
                    } else if office.isVerified {
                        Text(office.orderingNote)
                    } else if !child.birthStateCode.isEmpty {
                        Text("We do not yet carry verified detail for this state, so the birth certificate task links to the federal directory, which has a state-by-state picker.")
                    }
                }

                if !isDraft {
                    Section {
                        Button("Archive this child", role: .destructive) {
                            child.tombstone(in: context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(child.name.isEmpty ? "New child" : child.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .onAppear {
                if originalBirthStateCode == nil {
                    originalBirthStateCode = child.birthStateCode
                }
            }
            .toolbar {
                // A sheet that can create a child and cannot cancel one is a
                // trap: the only ways out were Done and a swipe, and the swipe
                // used to keep everything the app had guessed.
                if isDraft {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isDraft ? "Add" : "Done", action: confirm)
                        .disabled(!canSave)
                }
            }
        }
    }

    /// The only path that turns a draft into a child. Clearing the tombstone is
    /// what makes it visible to every query and to the requirement engine, so a
    /// plan is generated from confirmed answers rather than from defaults.
    private func confirm() {
        if isDraft { child.deletedAt = nil }
        if originalBirthStateCode != child.birthStateCode {
            child.birthCounty = ""
        }
        child.recordLocalChange(in: context)
        RequirementEngine.reconcile(
            child: child,
            profile: FamilyProfileStore.current(in: context),
            in: context
        )
        Task {
            await DeadlineReminderScheduler.reschedule(in: context)
        }
        onConfirm?()
        dismiss()
    }
}

// MARK: - County

/// A picker where the Census has a list, a text field where it does not.
///
/// Shared between the intake and the editor so the two cannot disagree about
/// what a county is. It routes nothing: see `USCounties` for why a generated
/// list of three thousand clerks would be worse than the state-level link a
/// human has actually read.
struct CountyField: View {
    let stateCode: String
    @Binding var county: String

    var body: some View {
        let counties = USCounties.names(forStateCode: stateCode)
        if stateCode.isEmpty || counties.isEmpty {
            TextField("County (optional)", text: $county)
        } else {
            Picker("County (optional)", selection: $county) {
                Text("Not sure").tag("")
                ForEach(counties, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }
}
