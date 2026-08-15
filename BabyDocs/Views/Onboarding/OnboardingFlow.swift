import SwiftData
import SwiftUI

/// The intake.
///
/// The rule that shaped this: no question that does not fork a rule. It is
/// tempting to ask for the hospital, the pediatrician and the weight, and all
/// three would make the app feel thorough and none of them would change a single
/// deadline. Every field here is read by `RequirementCatalog`.
///
/// The optional four used to be four unexplained toggles on one screen called
/// "Plans". That screen was where somebody opted out of a $1,000 federal
/// contribution because a switch did not say what it was. They are one page each
/// now, and each page answers the same three questions in the same order: what
/// it is, why it might matter to *you*, and what saying yes actually adds to
/// your list. Nobody should have to already know.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @State private var step: Step = .welcome
    @State private var navigator = AppNavigator.shared
    @State private var location = LocationLookup()

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

    // The optional four
    @State private var takingParentalLeave = true
    @State private var wantsNewbornAccount = true
    @State private var wants529 = false
    @State private var wantsPassport = false

    @State private var result: RequirementEngine.Result?

    enum Step: Int, CaseIterable {
        case welcome, baby, household, coverage
        case leave, newbornAccount, plan529, passport
        case done
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcomeStep
                case .baby: babyStep
                case .household: householdStep
                case .coverage: coverageStep
                case .leave: leaveStep
                case .newbornAccount: newbornAccountStep
                case .plan529: plan529Step
                case .passport: passportStep
                case .done: doneStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome && step != .done {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { back() }
                    }
                    ToolbarItem(placement: .principal) {
                        StepDots(current: step)
                    }
                }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: AppTheme.spacing) {
                Image(systemName: "folder.badge.person.crop")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                Text("The paperwork, in order")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Answer a few questions about your household and you get the tasks that actually apply to you, the dates that actually close, and a link to the office that actually issues each thing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: AppTheme.spacing) {
                // The "two windows close fast" line used to live here as fine
                // print under a button, which is the worst place for it: it is
                // jargon, and it is on the one screen where nothing can be done
                // about it. The explanation now sits on the coverage question,
                // where it is the decision being made.
                Button {
                    step = .baby
                } label: {
                    Text("Get started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Nothing you enter leaves this phone. Baby Docs has no account, and nowhere to keep a copy of your answers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Baby

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
                countyPicker(stateCode: birthStateCode, selection: $birthCounty)
            } header: {
                Text("Where the birth was registered")
            } footer: {
                Text("The birth certificate is issued where the birth was registered, not where you live now. In many states a county office is faster than the state one, which is the only reason the county is asked for.")
            }

            Section {
                Toggle("US citizen", isOn: $isUSCitizen)
            } footer: {
                Text("One task turns on this: a federal account for newborn citizens, explained in a moment.")
            }

            continueButton(enabled: !birthStateCode.isEmpty) { step = .household }
        }
        .navigationTitle("Your baby")
    }

    // MARK: - Household

    private var householdStep: some View {
        Form {
            Section {
                locationButton
                statePicker("State you live in", selection: $residenceStateCode)
            } header: {
                Text("Where you live")
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

    /// Fills the residence state and county from one location fix.
    ///
    /// Only offered on this question, never on the birth one. Where you are
    /// standing today is good evidence about where you live and poor evidence
    /// about where you gave birth, and a plan built on a silently wrong birth
    /// state sends a parent to the wrong vital records office for a fortnight.
    @ViewBuilder
    private var locationButton: some View {
        switch location.status {
        case .working, .asking:
            HStack {
                ProgressView()
                Text("Finding your county").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        default:
            Button {
                Task {
                    await location.find()
                    if case .done(let place) = location.status {
                        residenceStateCode = place.stateCode
                        if birthStateCode.isEmpty { birthStateCode = place.stateCode }
                        if birthCounty.isEmpty { birthCounty = place.county }
                    }
                }
            } label: {
                Label("Use my location", systemImage: "location")
            }
        }
    }

    // MARK: - Coverage

    private var coverageStep: some View {
        Form {
            Section {
                Text("Two deadlines in this app are real doors closing. Both of them are here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.clear)

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
                Text("A job-based plan must let you add the baby for at least 30 days after the birth. The Marketplace is generally 60. Miss the window and you usually wait for open enrollment, so this sets the hardest date in the app. If you are covered both ways, pick the job-based plan: it is the shorter one.")
            }

            Section {
                Toggle("We have a dependent care FSA", isOn: $hasDependentCareFSA)
            } footer: {
                Text("A separate election from the health plan, with its own window, and the one people most often miss because they assume the two move together. They do not.")
            }

            continueButton(enabled: insuranceKind != .unknown) { step = .leave }
        }
        .navigationTitle("Coverage")
    }

    // MARK: - The optional four, one page each

    private var leaveStep: some View {
        ExplainedChoice(
            symbol: "briefcase",
            title: "Is anyone taking parental leave?",
            what: "Paid or unpaid time off after the birth, whether it comes from your employer, from a state programme, or from unpaid job protection under federal law.",
            why: "The states that run paid family leave mostly require the claim inside a window measured in weeks, and it is the one piece of newborn paperwork that pays you rather than costing you. Federal job protection is separate again and has its own notice rules. Nobody hands you this: you file for it.",
            adds: "A task with your state's own programme, the federal rules that sit behind it, and what your employer needs from you.",
            isOn: $takingParentalLeave,
            toggleLabel: "Someone is taking leave"
        ) { step = .newbornAccount }
        .navigationTitle("Leave")
    }

    private var newbornAccountStep: some View {
        ExplainedChoice(
            symbol: "dollarsign.circle",
            title: "Claim the $1,000 newborn account?",
            what: "A one-time $1,000 federal contribution into an investment account for children born between 2025 and 2028. The IRS calls these Trump Accounts, which is the name you will see on irs.gov and on the form itself.",
            why: "It is a thousand dollars, it applies to most US citizen newborns, and almost nobody has heard of it. It is claimed by election rather than automatically, so a family that does not know about it simply does not get it. The election needs the baby's Social Security number first, which is why that task sits at the top of your plan.",
            adds: "A task that waits for the SSN, then points at the IRS page and the current form instructions.",
            isOn: $wantsNewbornAccount,
            toggleLabel: "Add this to my plan",
            isAvailable: isUSCitizen,
            unavailableNote: "This one is for US citizen children only, and you said this baby is not one, so it stays off your plan."
        ) { step = .plan529 }
        .navigationTitle("Newborn account")
    }

    private var plan529Step: some View {
        ExplainedChoice(
            symbol: "graduationcap",
            title: "Open a 529?",
            what: "A tax-advantaged savings account for education. Most states run their own, several give residents a state tax deduction for paying into it, and you can use another state's if theirs is better.",
            why: "Nothing about a 529 is urgent, and this app will not pretend otherwise: there is no deadline and no penalty for opening one next year. It is here because it is far easier to do in the same fortnight you are already gathering a birth certificate and a Social Security number than it is to come back to in eighteen months.",
            adds: "One unhurried task with your state's own plan and what opening an account asks for.",
            isOn: $wants529,
            toggleLabel: "Add this to my plan"
        ) { step = .passport }
        .navigationTitle("529")
    }

    private var passportStep: some View {
        ExplainedChoice(
            symbol: "airplane",
            title: "Will the baby need a passport?",
            what: "A US passport for a child under 16. Both parents have to appear in person with the child, or the absent one has to send a notarised consent form.",
            why: "The in-person rule is what catches people out, and so is the order of operations: the application needs a certified birth certificate, so it cannot start until that has arrived. If there is a trip in the first year, this is the task that has to be started earliest and is almost always started last.",
            adds: "A task that stays blocked until the certificate is in hand, then explains the appointment and who has to be at it.",
            isOn: $wantsPassport,
            toggleLabel: "Add this to my plan"
        ) { finish() }
        .navigationTitle("Passport")
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: AppTheme.spacing) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
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
                    .padding(.top, AppTheme.tightSpacing)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: AppTheme.spacing) {
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

    /// A picker once a state is chosen, and nothing at all before that.
    ///
    /// The old free-text field produced "Alameda", "alameda co", and "Alameda
    /// County" for one place, which is fine for a display string and useless for
    /// anything else. Note that the county still routes nothing: the birth
    /// certificate link comes from `StateVitalRecords`, which a human has read.
    @ViewBuilder
    private func countyPicker(stateCode: String, selection: Binding<String>) -> some View {
        let counties = USCounties.names(forStateCode: stateCode)
        if stateCode.isEmpty {
            EmptyView()
        } else if counties.isEmpty {
            TextField("County (optional)", text: selection)
        } else {
            Picker("County (optional)", selection: selection) {
                Text("Not sure").tag("")
                ForEach(counties, id: \.self) { county in
                    Text(county).tag(county)
                }
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
        guard var previous = Step(rawValue: step.rawValue - 1) else { return }
        // Skip a page that was skipped on the way in, so Back does not land on
        // a question the flow decided was not applicable.
        if previous == .newbornAccount && !isUSCitizen {
            previous = .leave
        }
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
        profile.wantsNewbornAccount = wantsNewbornAccount
        profile.takingParentalLeave = takingParentalLeave
        profile.recordLocalChange(in: context)

        let child = Child(name: name, birthDate: birthDate, birthStateCode: birthStateCode)
        child.birthCounty = birthCounty
        child.isUSCitizen = isUSCitizen
        context.insert(child)
        child.recordLocalChange(in: context)

        result = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        step = .done
    }

    private func allTasks() -> [RequirementTask] {
        ((try? context.fetch(FetchDescriptor<Child>())) ?? []).flatMap(\.liveTasks)
    }
}

// MARK: - One question, explained

/// The page shape the four optional questions share.
///
/// Three headings in a fixed order, because the order is the argument: *what it
/// is* before *why it might matter to you* before *what it adds*. A toggle with
/// a four-word label asks someone to make a decision using knowledge they were
/// never given, and then quietly records the answer as though they had.
struct ExplainedChoice: View {
    let symbol: String
    let title: String
    let what: String
    let why: String
    let adds: String
    @Binding var isOn: Bool
    let toggleLabel: String
    var isAvailable: Bool = true
    var unavailableNote: String = ""
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    Image(systemName: symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, AppTheme.tightSpacing)
            }
            .listRowBackground(Color.clear)

            Section("What it is") {
                Text(what).fixedSize(horizontal: false, vertical: true)
            }

            Section("Why it might matter to you") {
                Text(why).fixedSize(horizontal: false, vertical: true)
            }

            Section("What it adds to your plan") {
                Text(adds).fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if isAvailable {
                    Toggle(toggleLabel, isOn: $isOn)
                } else {
                    Text(unavailableNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("You can change this later in the household answers without redoing any of this.")
            }

            Section {
                Button(action: onContinue) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Where you are in the intake. Ten screens without this reads as an unbounded
/// form; with it, it reads as a short one you are most of the way through.
struct StepDots: View {
    let current: OnboardingFlow.Step

    private var steps: [OnboardingFlow.Step] {
        OnboardingFlow.Step.allCases.filter { $0 != .welcome && $0 != .done }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(steps, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Question \(current.rawValue) of \(steps.count)")
    }
}

#Preview {
    OnboardingFlow()
        .modelContainer(BabyModelStore.makeInMemoryContainer())
}
