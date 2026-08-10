import SwiftData
import SwiftUI

/// The intake. Six screens, and every question on them changes what ends up in
/// the plan.
///
/// The rule that shaped this: no question that does not fork a rule. It is
/// tempting to ask for the hospital, the pediatrician and the weight, and all
/// three would make the app feel thorough and none of them would change a single
/// deadline. Every field here is read by `RequirementCatalog`, and the last
/// screen proves it by showing what the answers produced.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @State private var step: Step = .welcome
    @State private var navigator = AppNavigator.shared

    // Baby
    @State private var name = ""
    @State private var birthDate = Date()
    @State private var birthStateCode = ""
    @State private var birthCounty = ""
    @State private var isUSCitizen = true

    // Household
    @State private var residenceStateCode = ""
    @State private var parentage: ParentageSituation = .married
    @State private var secondParentOnRecord = true
    @State private var insuranceKind: InsuranceKind = .unknown
    @State private var hasDependentCareFSA = false
    @State private var wantsPassport = false
    @State private var wants529 = false
    @State private var wantsTrumpAccount = true
    @State private var takingParentalLeave = true

    @State private var result: RequirementEngine.Result?
    @State private var isJoining = false

    enum Step: Int, CaseIterable {
        case welcome, baby, household, coverage, extras, done
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcomeStep
                case .baby: babyStep
                case .household: householdStep
                case .coverage: coverageStep
                case .extras: extrasStep
                case .done: doneStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome && step != .done {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { back() }
                    }
                }
            }
            .sheet(isPresented: $isJoining) {
                JoinFamilyView()
            }
            .onChange(of: navigator.pendingInviteCode) { _, code in
                if code != nil { isJoining = true }
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.person.crop")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("The paperwork, in order")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Tell us where you live and how you are covered. You get the tasks that actually apply to you, the dates that actually close, and a link to the office that actually issues each thing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 10) {
                Text("Two windows close fast: 30 days for a job-based health plan, 60 days for the Marketplace. Everything else is slower than people fear.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button {
                    step = .baby
                } label: {
                    Text("Get started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("I have an invitation") { isJoining = true }
                    .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var babyStep: some View {
        Form {
            Section {
                TextField("First name (optional)", text: $name)
                DatePicker(
                    "Date of birth",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
            } header: {
                Text("Your baby")
            } footer: {
                Text("The date of birth is what every deadline in the app counts from, so it is the one answer worth double-checking.")
            }

            Section {
                statePicker("State of birth", selection: $birthStateCode)
                TextField("County (optional)", text: $birthCounty)
            } footer: {
                Text("The birth certificate is issued where the birth was registered, not where you live. In many states a county office is faster than the state one.")
            }

            Section {
                Toggle("US citizen", isOn: $isUSCitizen)
            } footer: {
                Text("Used only to decide whether the Trump Account task applies.")
            }

            continueButton(enabled: !birthStateCode.isEmpty) { step = .household }
        }
        .navigationTitle("Your baby")
    }

    private var householdStep: some View {
        Form {
            Section {
                statePicker("State you live in", selection: $residenceStateCode)
            } footer: {
                Text("Decides the Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with.")
            }

            Section("Parents") {
                Picker("Situation", selection: $parentage) {
                    ForEach(ParentageSituation.allCases.filter { $0 != .unknown }, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if parentage == .unmarriedBothParents {
                    Toggle("Both parents already on the birth record", isOn: $secondParentOnRecord)
                }
            }

            if parentage == .unmarriedBothParents && !secondParentOnRecord {
                Section {
                    Text("Establishing the second parent is state law and legally significant. The app will show you the task and your state's own form. It will not prepare or file anything for you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            continueButton(enabled: !residenceStateCode.isEmpty) { step = .coverage }
        }
        .navigationTitle("Your household")
    }

    private var coverageStep: some View {
        Form {
            Section {
                Picker("Coverage", selection: $insuranceKind) {
                    ForEach(InsuranceKind.allCases.filter { $0 != .unknown }, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("How is the family covered?")
            } footer: {
                Text("This sets the hardest date in the app. Job-based plans must allow at least 30 days after a birth; the Marketplace is generally 60. If you are covered both ways, pick the job-based plan: it is the shorter window.")
            }

            Section {
                Toggle("We have a dependent care FSA", isOn: $hasDependentCareFSA)
            } footer: {
                Text("A separate election from the health plan, with its own window, and the one people most often miss.")
            }

            continueButton(enabled: insuranceKind != .unknown) { step = .extras }
        }
        .navigationTitle("Coverage")
    }

    private var extrasStep: some View {
        Form {
            Section {
                Toggle("Someone is taking parental leave", isOn: $takingParentalLeave)
                Toggle("We want a passport for the baby", isOn: $wantsPassport)
                Toggle("We want to open a 529", isOn: $wants529)
                Toggle("We want the Trump Account contribution", isOn: $wantsTrumpAccount)
            } header: {
                Text("Anything else?")
            } footer: {
                Text("Turning one off just keeps it off the plan. You can turn any of them back on later without redoing this.")
            }

            continueButton(enabled: true) { finish() }
        }
        .navigationTitle("Plans")
    }

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                Text("Your plan is ready")
                    .font(.title.weight(.bold))
                if let result {
                    Text("\(result.total) tasks apply to your family.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Text(PlanExporter.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    Task {
                        // Asked here, and only here, because this is the first
                        // moment there is a real closing window to be reminded
                        // about. Asked on launch it reads as noise and gets
                        // refused permanently, and a refused prompt is the one
                        // thing the app cannot undo.
                        await NotificationService.shared.requestAuthorization()
                        await DeadlineReminderScheduler.reschedule(for: allTasks())
                    }
                } label: {
                    Text("Remind me before deadlines").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now") { }
                    .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Pieces

    private func statePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Select").tag("")
            ForEach(USState.all) { state in
                Text(state.name).tag(state.code)
            }
        }
    }

    private func continueButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Section {
            Button(action: action) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!enabled)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func finish() {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = residenceStateCode
        profile.parentage = parentage
        profile.secondParentOnRecord = parentage == .married || secondParentOnRecord
        profile.insuranceKind = insuranceKind
        profile.hasDependentCareFSA = hasDependentCareFSA
        profile.wantsPassport = wantsPassport
        profile.wants529 = wants529
        profile.wantsTrumpAccount = wantsTrumpAccount
        profile.takingParentalLeave = takingParentalLeave
        profile.recordLocalChange(in: context)

        let child = Child(name: name, birthDate: birthDate, birthStateCode: birthStateCode)
        child.birthCounty = birthCounty
        child.isUSCitizen = isUSCitizen
        child.groupID = FamilyService.shared.activeGroupID
        context.insert(child)
        child.recordLocalChange(in: context)

        result = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        step = .done
    }

    private func allTasks() -> [RequirementTask] {
        ((try? context.fetch(FetchDescriptor<Child>())) ?? []).flatMap(\.liveTasks)
    }
}

#Preview {
    OnboardingFlow()
        .modelContainer(BabyModelStore.makeInMemoryContainer())
}
