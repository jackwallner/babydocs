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
    @State private var original: HouseholdSnapshot?

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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let profile, !profile.residenceStateCode.isEmpty else { return }
                        let result = RequirementEngine.reconcileAll(in: context)
                        guard result.didPersist else { return }
                        Task {
                            await DeadlineReminderScheduler.reschedule(in: context)
                        }
                        dismiss()
                    }
                    .disabled(profile?.residenceStateCode.isEmpty != false)
                }
            }
            .interactiveDismissDisabled()
            .onAppear {
                if profile == nil {
                    let current = FamilyProfileStore.current(in: context)
                    profile = current
                    original = HouseholdSnapshot(profile: current)
                }
            }
        }
    }

    private func cancel() {
        guard let profile, let original else {
            dismiss()
            return
        }
        original.apply(to: profile)
        if profile.recordLocalChange(in: context) {
            dismiss()
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
                    set: {
                        profile.parentage = $0
                        if $0 != .unmarriedBothParents {
                            profile.secondParentOnRecord = false
                        }
                    }
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
                    set: {
                        profile.insuranceKind = $0
                        if $0 != .marketplace {
                            profile.marketplaceKind = .unknown
                        }
                        if $0 != .employer {
                            profile.employerPlanName = ""
                            profile.benefitsContactNote = ""
                        }
                    }
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

private struct HouseholdSnapshot {
    let residenceStateCode: String
    let parentage: ParentageSituation
    let secondParentOnRecord: Bool
    let insuranceKind: InsuranceKind
    let marketplaceKind: MarketplaceKind
    let employerPlanName: String
    let benefitsContactNote: String
    let hasDependentCareFSA: Bool
    let parentalLeaveTakers: ParentalLeaveTakers
    let wantsNewbornAccount: Bool
    let wants529: Bool
    let wantsPassport: Bool

    init(profile: FamilyProfile) {
        residenceStateCode = profile.residenceStateCode
        parentage = profile.parentage
        secondParentOnRecord = profile.secondParentOnRecord
        insuranceKind = profile.insuranceKind
        marketplaceKind = profile.marketplaceKind
        employerPlanName = profile.employerPlanName
        benefitsContactNote = profile.benefitsContactNote
        hasDependentCareFSA = profile.hasDependentCareFSA
        parentalLeaveTakers = profile.parentalLeaveTakers
        wantsNewbornAccount = profile.wantsNewbornAccount
        wants529 = profile.wants529
        wantsPassport = profile.wantsPassport
    }

    func apply(to profile: FamilyProfile) {
        profile.residenceStateCode = residenceStateCode
        profile.parentage = parentage
        profile.secondParentOnRecord = secondParentOnRecord
        profile.insuranceKind = insuranceKind
        profile.marketplaceKind = marketplaceKind
        profile.employerPlanName = employerPlanName
        profile.benefitsContactNote = benefitsContactNote
        profile.hasDependentCareFSA = hasDependentCareFSA
        profile.parentalLeaveTakers = parentalLeaveTakers
        profile.wantsNewbornAccount = wantsNewbornAccount
        profile.wants529 = wants529
        profile.wantsPassport = wantsPassport
    }
}
