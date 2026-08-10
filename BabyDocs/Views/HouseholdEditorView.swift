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
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if profile == nil { profile = FamilyProfileStore.current(in: context) }
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
                    ForEach(ParentageSituation.allCases.filter { $0 != .unknown }, id: \.self) { value in
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
                    ForEach(InsuranceKind.allCases.filter { $0 != .unknown }, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                TextField("Plan name (optional)", text: $profile.employerPlanName)
                Toggle("Dependent care FSA", isOn: $profile.hasDependentCareFSA)
            } header: {
                Text("Health coverage")
            } footer: {
                Text("If you are covered both through a job and through the Marketplace, pick the job-based plan: it is the shorter window, and it is the one that closes first.")
            }

            Section("Plans") {
                Toggle("Taking parental leave", isOn: $profile.takingParentalLeave)
                Toggle("Want a passport", isOn: $profile.wantsPassport)
                Toggle("Want a 529", isOn: $profile.wants529)
                Toggle("Want the Trump Account contribution", isOn: $profile.wantsTrumpAccount)
            }
        }
    }
}
