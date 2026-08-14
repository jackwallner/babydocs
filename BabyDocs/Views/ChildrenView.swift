import SwiftData
import SwiftUI

struct ChildrenView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]

    @State private var editingChild: Child?
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
                } header: {
                    Text("Children")
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
            .sheet(item: $editingChild) { child in
                ChildEditorSheet(child: child)
            }
            .sheet(isPresented: $isEditingHousehold) {
                HouseholdEditorView()
            }
        }
    }

    private func addChild() {
        guard store.isPro || children.isEmpty else {
            navigator.requestUpgrade()
            return
        }
        let child = Child(birthDate: Date())
        child.colorIndex = children.count
        // Inherit the household's state, which is right far more often than it
        // is wrong, and is trivially corrected on the sheet that opens next.
        child.birthStateCode = FamilyProfileStore.current(in: context).residenceStateCode
        context.insert(child)
        child.recordLocalChange(in: context)
        editingChild = child
    }
}

private struct ChildRow: View {
    let child: Child

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(child.color.opacity(0.18))
                Text(child.initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(child.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(child.displayName).font(.body)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            let overview = TaskPlanner.overview(for: child.liveTasks)
            Text("\(overview.openCount)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(overview.overdueCount > 0 ? .red : .secondary)
        }
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
    }
}

// MARK: - Editor

struct ChildEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var child: Child

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
                    if office.isVerified {
                        Text(office.orderingNote)
                    } else if !child.birthStateCode.isEmpty {
                        Text("We do not yet carry verified detail for this state, so the birth certificate task links to the federal directory, which has a state-by-state picker.")
                    }
                }

                Section {
                    Button("Remove this child", role: .destructive) {
                        child.tombstone(in: context)
                        dismiss()
                    }
                }
            }
            .navigationTitle(child.name.isEmpty ? "New child" : child.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        child.recordLocalChange(in: context)
                        RequirementEngine.reconcile(
                            child: child,
                            profile: FamilyProfileStore.current(in: context),
                            in: context
                        )
                        dismiss()
                    }
                }
            }
        }
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
