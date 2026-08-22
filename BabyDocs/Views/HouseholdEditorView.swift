import SwiftData
import SwiftUI

/// The household answers, editable after the intake.
///
/// Every control here rebuilds every child's plan on dismissal, not on change.
/// Reconciling on each keystroke would be correct and would also make a task
/// appear and disappear under the finger of someone still deciding.
struct HouseholdEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var profile: FamilyProfile?

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    form(for: profile)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let profile {
                            profile.recordLocalChange(in: context)
                            RequirementEngine.reconcileAll(in: context)
                            Task {
                                await DeadlineReminderScheduler.reschedule(in: context)
                            }
                        }
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled()
            .onAppear {
                if profile == nil { profile = FamilyProfileStore.current(in: context) }
            }
        }
    }

    private func labelledToggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func form(for profile: FamilyProfile) -> some View {
        @Bindable var profile = profile
        Form {
            Section {
                Picker("State you live in", selection: $profile.residenceStateCode) {
                    Text("Select").tag("")
                    ForEach(USState.all) { state in
                        Text(state.name).tag(state.code)
                    }
                }
            } footer: {
                Text("Decides the Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with.")
            }

            Section("Parents") {
                Picker("Situation", selection: Binding(
                    get: { profile.parentage },
                    set: { profile.parentage = $0 }
                )) {
                    ForEach(ParentageSituation.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                if profile.parentage == .unmarriedBothParents {
                    Toggle("Both parents on the birth record", isOn: $profile.secondParentOnRecord)
                }
            }

            Section {
                Picker("Coverage", selection: Binding(
                    get: { profile.insuranceKind },
                    set: { profile.insuranceKind = $0 }
                )) {
                    ForEach(InsuranceKind.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                if profile.insuranceKind == .marketplace {
                    Picker("Marketplace", selection: Binding(
                        get: { profile.marketplaceKind },
                        set: { profile.marketplaceKind = $0 }
                    )) {
                        ForEach(MarketplaceKind.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }
                if profile.insuranceKind == .employer {
                    TextField("Plan or employer name", text: $profile.employerPlanName)
                        .textInputAutocapitalization(.words)
                    TextField("Benefits contact or phone", text: $profile.benefitsContactNote)
                }
                Toggle("Dependent care FSA", isOn: $profile.hasDependentCareFSA)
            } header: {
                Text("Health coverage")
            } footer: {
                Text("If you are covered both through a job and through the Marketplace, pick the job-based plan: it is the shorter window, and it is the one that closes first. \"Not sure yet\" is a real answer: it puts a task at the top of your plan about finding out, rather than a deadline the app guessed at.")
            }

            // Bare toggles are fine *here* and were not fine in the intake.
            // Someone in this screen has already read the page that explained
            // each of these and is coming back to change their mind; someone in
            // the intake had never heard of any of them. The subtitles carry
            // enough to jog a memory without repeating four screens of prose.
            Section {
                Picker("Parental leave", selection: Binding(
                    get: { profile.parentalLeaveTakers },
                    set: { profile.parentalLeaveTakers = $0 }
                )) {
                    ForEach(ParentalLeaveTakers.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                labelledToggle(
                    "The $1,000 newborn account",
                    "A one-time federal contribution for citizen children born 2025 to 2028. The IRS calls these Trump Accounts.",
                    isOn: $profile.wantsNewbornAccount
                )
                labelledToggle(
                    "A 529",
                    "Education savings. No deadline, easier now than in eighteen months.",
                    isOn: $profile.wants529
                )
                labelledToggle(
                    "A passport",
                    "Needs the certified birth certificate first, and both parents in person.",
                    isOn: $profile.wantsPassport
                )
            } header: {
                Text("Optional tasks")
            } footer: {
                Text("Both parents taking leave means two claims, with two employers and two windows, so it puts two tasks on the plan rather than one.")
            }
        }
    }
}
