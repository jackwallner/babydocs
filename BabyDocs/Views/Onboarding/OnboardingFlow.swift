import SwiftData
import SwiftUI

/// The intake.
///
/// Two rules shaped it. **No question that does not fork a rule**: it is
/// tempting to ask for the hospital, the pediatrician and the weight, and all
/// three would make the app feel thorough and none of them would change a single
/// deadline. Every field here is read by `RequirementCatalog`.
///
/// And **no paragraph that is not about the answer being given**. The intake
/// used to carry an essay on each screen, including one on the welcome page
/// about where the answers are stored, which is a fine thing to be able to look
/// up and a strange thing to put in front of somebody who has not typed
/// anything yet. What survived is either short enough to sit in a footer where
/// it will actually be read, or genuinely worth a tap on a question a reader
/// has never heard of, like the $1,000 newborn account.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @State private var step: Step = .welcome
    @State private var location = LocationLookup()

    // Baby
    @State private var name = ""
    @State private var birthDate = Date()
    @State private var birthStateCode = ""
    @State private var birthCounty = ""
    @State private var isUSCitizen = true

    // Household
    @State private var residenceStateCode = ""
    /// What the location fix filled in, so the screens can say so rather than
    /// quietly presenting a guess as an answer.
    @State private var prefilledFromLocation: LocationLookup.Place?
    // Neutral by default, all three of them. Each one changes which tasks are
    // generated, so a value the parent never chose is a plan the parent never
    // chose: "married" quietly decides a parentage question, and "already on the
    // record" quietly removes the task about getting there.
    @State private var parentage: ParentageSituation = .unknown
    @State private var secondParentOnRecord = false
    @State private var insuranceKind: InsuranceKind = .unknown
    @State private var marketplaceKind: MarketplaceKind = .unknown
    @State private var employerPlanName = ""
    @State private var benefitsContactNote = ""
    @State private var hasDependentCareFSA = false

    // The optional four. A question is not an answer, so each starts off until
    // the parent explicitly adds it to the plan.
    @State private var leaveTakers: ParentalLeaveTakers = .nobody
    @State private var wantsNewbornAccount = false
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

    /// A scroll view rather than two `Spacer`s around a fixed block.
    ///
    /// The fixed version looked correct at every size somebody checked and
    /// truncated the product's whole promise to an ellipsis at an accessibility
    /// text size: the title, the explanation and the privacy line all clipped at
    /// once, on the first screen, for exactly the readers who need large text.
    /// Scrolling costs a well-sighted parent nothing here and is the difference
    /// between readable and not for everyone else.
    private var welcomeStep: some View {
        CentredIfItFits {
            VStack(spacing: AppTheme.spacing) {
                Image(systemName: "folder.badge.person.crop")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                Text("The paperwork, in order")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Answer a few questions about your household and you get the tasks that actually apply to you, the dates that actually close, and a link to the office that actually issues each thing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(title: "Get started", note: "About a minute. Nothing is submitted anywhere.") {
                step = .baby
            }
        }
    }

    // MARK: - Baby

    private var babyStep: some View {
        Form {
            Section {
                TextField("First name (optional)", text: $name)
                DatePicker(
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                ) {
                    RequiredLabel("Date of birth")
                }
            } header: {
                Text("Your baby")
            } footer: {
                Text("Every deadline in the app counts from this date, so it is the one answer worth double-checking.")
            }

            Section {
                locationButton
                statePicker("State of birth", selection: $birthStateCode, required: true)
                countyPicker(stateCode: birthStateCode, selection: $birthCounty)
                Toggle("US citizen", isOn: $isUSCitizen)
            } header: {
                Text("Where the birth was registered")
            } footer: {
                Text(birthFooter)
            }
        }
        .navigationTitle("Your baby")
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(
                enabled: !birthStateCode.isEmpty,
                note: birthStateCode.isEmpty ? "Pick the state of birth to carry on." : ""
            ) { step = .household }
        }
    }

    private var birthFooter: String {
        if let place = prefilledFromLocation {
            let county = place.county.isEmpty ? "" : "\(place.county), "
            return "From where you are now: \(county)\(USState.displayName(for: place.stateCode)). Where you live has been set to the same state. Change either if the birth was somewhere else."
        }
        if birthStateCode.isEmpty {
            return "The certificate comes from where the birth was registered, not from where you live now."
        }
        return "The certificate comes from where the birth was registered. The county is asked for because in many states its office is faster than the state one."
    }

    /// Fills the birth state and county, and the residence state with them.
    ///
    /// This used to be offered on the household question only, on the reasoning
    /// that where you are standing is poor evidence about where you gave birth.
    /// The reasoning was right about *silent* inference and wrong about the
    /// button: the likeliest thing by a distance is that a parent is using this
    /// app in the state the birth was registered in, and typing the same state
    /// twice on two screens is a worse experience than reading one sentence that
    /// says exactly what was filled in and inviting a correction.
    ///
    /// So it fills both, it says so underneath in words, and both pickers stay
    /// editable and visible. Nothing here is inferred without being shown.
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
                        birthStateCode = place.stateCode
                        birthCounty = place.county
                        residenceStateCode = place.stateCode
                        prefilledFromLocation = place
                    }
                }
            } label: {
                Label("Use my location to fill these in", systemImage: "location")
            }
        }
    }

    // MARK: - Household

    private var householdStep: some View {
        Form {
            Section {
                statePicker("State you live in", selection: $residenceStateCode, required: true)
            } header: {
                Text("Where you live")
            } footer: {
                Text(residenceFooter)
            }

            // "Prefer not to say" is a real answer here, not a hidden case.
            //
            // It exists in the model and the intake used to filter it out, which
            // left a parent who is separated, in a contested situation, or
            // simply not willing to tell an app about it picking a value that
            // was false. A false value is worse than no value: it is what turns
            // the legally significant parentage task on or off.
            Section {
                Picker("Situation", selection: $parentage) {
                    ForEach(ParentageSituation.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if parentage == .unmarriedBothParents {
                    Toggle("Both parents already on the birth record", isOn: $secondParentOnRecord)
                }
            } header: {
                Text("Parents")
            } footer: {
                Text(parentageFooter)
            }
        }
        .navigationTitle("Your household")
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(
                enabled: !residenceStateCode.isEmpty,
                note: residenceStateCode.isEmpty ? "Pick the state you live in to carry on." : ""
            ) { step = .coverage }
        }
    }

    private var residenceFooter: String {
        let base = "Sets your Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with."
        if let place = prefilledFromLocation, place.stateCode == residenceStateCode {
            return "Filled in from your location. " + base
        }
        return base
    }

    private var parentageFooter: String {
        switch parentage {
        case .unknown:
            return "This decides one task: establishing a second parent who is not automatically on the birth record. Left as it is, that task stays off, and you can turn it on later without redoing anything."
        case .unmarriedBothParents where !secondParentOnRecord:
            return "In most states marriage puts the second parent on the record automatically and an unmarried second parent has to establish it deliberately. Your plan will carry that task and your state's own form. Baby Docs will not prepare or file it for you."
        default:
            return "This decides one task: in most states marriage puts the second parent on the record automatically, and an unmarried second parent has to establish it deliberately."
        }
    }

    // MARK: - Coverage

    private var coverageStep: some View {
        Form {
            Section {
                Picker("Coverage", selection: $insuranceKind) {
                    ForEach(InsuranceKind.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("How is the family covered?")
            } footer: {
                // The single most important sentence in the intake, so it is
                // printed rather than folded away behind a disclosure. A job
                // plan and the Marketplace are the only two hard doors in the
                // app, and a reader who never taps "why" is exactly the reader
                // who needs to know this.
                Text(coverageFooter)
            }

            // Asked because it changes where the family has to go, not how long
            // they have. About a third of states run their own exchange, and a
            // parent sent to HealthCare.gov from one of them signs in, is told
            // it does not serve their state, and loses days inside a window that
            // does not stop for it.
            if insuranceKind == .marketplace {
                Section {
                    Picker("Marketplace", selection: $marketplaceKind) {
                        ForEach(MarketplaceKind.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Which marketplace?")
                } footer: {
                    Text("The 60 days is the same either way. The site and the sign-in are not: HealthCare.gov will tell a Californian it does not serve them.")
                }
            }

            // Asked here rather than left to a settings screen nobody opens,
            // because these two answers are what turn the hardest task in the
            // app from "add the baby to the job-based health plan" into a
            // sentence naming the plan and the person who can confirm the date.
            if insuranceKind == .employer {
                Section {
                    TextField("Plan or employer name", text: $employerPlanName)
                        .textInputAutocapitalization(.words)
                    TextField("Benefits contact or phone", text: $benefitsContactNote)
                } header: {
                    Text("Which plan? (optional)")
                } footer: {
                    Text("Both go onto the task and into the reminder, so the notification names the plan and who to ring. Neither changes the deadline, and neither leaves this phone.")
                }
            }

            Section {
                Toggle("We have a dependent care FSA", isOn: $hasDependentCareFSA)
            } footer: {
                Text("A separate election from the health plan, with its own window, and the one most often missed. Your employer sets that window rather than the law, so it is shown as a suggestion to confirm.")
            }
        }
        .navigationTitle("Coverage")
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: true) { step = .leave }
        }
    }

    private var coverageFooter: String {
        let base = "A job-based plan must let you add the baby within 30 days of the birth. The Marketplace gives 60. Miss it and you usually wait for open enrollment. Covered both ways? Pick the job plan: it closes first."
        if insuranceKind == .unknown {
            return base + " \"Not sure yet\" blocks nothing: you get a task about finding out instead of a date the app guessed."
        }
        return base
    }

    // MARK: - The optional four, one page each

    /// Not a toggle, because leave is not a household arrangement.
    ///
    /// It shipped as "someone is taking leave", which quietly decided that a
    /// family where both parents take leave has one piece of paperwork. They
    /// have two: two employers, two policies, often two different windows, and
    /// the second parent's claim is the one that gets forgotten precisely
    /// because nothing ever asked about it.
    private var leaveStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    Text("Who is taking parental leave?")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Paid or unpaid time off after the birth, whether it comes from an employer, from a state programme, or from unpaid job protection under federal law.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, AppTheme.tightSpacing)
            }
            .listRowBackground(Color.clear)

            Section {
                Picker("Leave", selection: $leaveTakers) {
                    ForEach(ParentalLeaveTakers.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(leaveFooter)
            }

            Section {
                OnboardingDisclosure(
                    label: "Why leave is the one that pays you",
                    text: "The states that run paid family leave mostly require the claim inside a window measured in weeks, and it is the one piece of newborn paperwork that pays you rather than costing you. Federal job protection under FMLA is separate again and has its own notice rules. Nobody hands you this: you file for it, with your own employer."
                )
            }
        }
        .navigationTitle("Leave")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: true) { step = isUSCitizen ? .newbornAccount : .plan529 }
        }
    }

    private var leaveFooter: String {
        switch leaveTakers {
        case .nobody:
            return "Nothing about leave goes on your plan. You can change this later without redoing any of this."
        case .oneParent:
            return "One task, with your state's own programme, the federal rules behind it, and what the employer needs from you."
        case .bothParents:
            return "Two tasks, one for each parent. Each claim goes to a different employer, and the rules for a second parent's bonding leave are often not the rules for the birth parent's."
        }
    }

    private var newbornAccountStep: some View {
        ExplainedChoice(
            symbol: "dollarsign.circle",
            title: "Claim the $1,000 newborn account?",
            what: "A one-time $1,000 federal contribution into an investment account for children born between 2025 and 2028. The IRS calls these Trump Accounts, which is the name you will see on irs.gov and on the form itself.",
            detailLabel: "Why almost nobody claims this",
            detail: "It is a thousand dollars, most US citizen newborns can qualify, and it is claimed by election rather than automatically, so a family that has not heard of it simply does not get it. The election needs the baby's Social Security number first, which is why that task sits at the top of your plan. Baby Docs cannot tell you whether you qualify: there are conditions beyond citizenship and a birth year, and the instructions are the only thing that settles them.",
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
            detailLabel: "Why now rather than in a year",
            detail: "Nothing about a 529 is urgent, and this app will not pretend otherwise: there is no deadline and no penalty for opening one next year. It is here because it is far easier to do in the same fortnight you are already gathering a birth certificate and a Social Security number than it is to come back to in eighteen months. Saying yes adds one unhurried task with your state's own plan and what opening an account asks for.",
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
            detailLabel: "Why this one has to start earliest",
            detail: "The application needs a certified birth certificate, so it cannot start until that has arrived, and the in-person rule is what catches people out. If there is a trip in the first year, this is the task that has to be started earliest and is almost always started last. It stays blocked on your plan until the certificate is in hand, then explains the appointment and who has to be at it.",
            isOn: $wantsPassport,
            toggleLabel: "Add this to my plan"
        ) { finish() }
        .navigationTitle("Passport")
    }

    // MARK: - Done

    private var doneStep: some View {
        CentredIfItFits {
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
                    .padding(.top, AppTheme.tightSpacing)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: AppTheme.tightSpacing) {
                if canOfferReminders {
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
                }

                Button("Not now") { }
                    .font(.subheadline)
                    .padding(.vertical, AppTheme.tightSpacing)
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.top, AppTheme.spacing)
            .padding(.bottom, AppTheme.tightSpacing)
            .background(.bar)
        }
    }

    // MARK: - Pieces

    private func statePicker(_ title: String, selection: Binding<String>, required: Bool = false) -> some View {
        Picker(selection: selection) {
            Text("Select").tag("")
            ForEach(USState.all) { state in
                Text(state.name).tag(state.code)
            }
        } label: {
            if required {
                RequiredLabel(title)
            } else {
                Text(title)
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
        profile.marketplaceKind = insuranceKind == .marketplace ? marketplaceKind : .unknown
        profile.employerPlanName = insuranceKind == .employer ? employerPlanName : ""
        profile.benefitsContactNote = insuranceKind == .employer ? benefitsContactNote : ""
        profile.hasDependentCareFSA = hasDependentCareFSA
        profile.wantsPassport = wantsPassport
        profile.wants529 = wants529
        profile.wantsNewbornAccount = wantsNewbornAccount
        profile.parentalLeaveTakers = leaveTakers
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

    private var canOfferReminders: Bool {
        !DeadlineReminderScheduler.plans(for: allTasks()).isEmpty
    }
}

// MARK: - One question, explained

/// The page shape the optional questions share.
///
/// *What it is* in plain sight, and one folded paragraph for the reader who has
/// never heard of the thing. It used to be two folded paragraphs, labelled "Why
/// it might matter to you" and "What it adds to your plan", which is a shape
/// rather than an answer: the labels were the same on every page, so they told a
/// reader nothing about which one was worth opening. One disclosure, and its
/// label says what is actually inside it.
struct ExplainedChoice: View {
    let symbol: String
    let title: String
    let what: String
    let detailLabel: String
    let detail: String
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
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(what)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, AppTheme.tightSpacing)
            }
            .listRowBackground(Color.clear)

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
                OnboardingDisclosure(label: detailLabel, text: detail)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: true, action: onContinue)
        }
    }
}

// MARK: - The shapes every question shares

/// A field the intake will not move on without.
///
/// Three screens in, the difference between "optional" and "the app cannot build
/// your plan without this" was invisible until Continue refused to work, which
/// reads as a broken button rather than as a missing answer. The star marks the
/// field, and `OnboardingFooter` says in words which one is missing.
struct RequiredLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    /// The label element keeps the plain title, and the star is hidden from
    /// accessibility rather than merged into it. Merging read better in one
    /// sense ("state of birth, required") and cost the row its identity for
    /// everything that looks a control up by name, VoiceOver's own rotor
    /// included. What is missing is said in words by the footer under Continue,
    /// which is spoken as well as drawn.
    var body: some View {
        HStack(spacing: 2) {
            Text(text)
            Text("*")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        }
    }
}

/// The footer that does not scroll away.
///
/// Continue used to be the last row of the form, which meant that on any
/// question long enough to scroll (most of them, at most text sizes) the way
/// forward was somewhere below the bottom of the screen. A reader who cannot
/// see the button assumes there is nothing there, and an intake that looks like
/// a dead end on question two is an intake that gets abandoned on question two.
struct OnboardingFooter: View {
    var title = "Continue"
    var enabled = true
    var note = ""
    let action: () -> Void

    init(title: String = "Continue", enabled: Bool = true, note: String = "", action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.note = note
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppTheme.tightSpacing) {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!enabled)

            if !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(enabled ? .secondary : Color.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppTheme.margin)
        .padding(.top, AppTheme.spacing)
        .padding(.bottom, AppTheme.tightSpacing)
        .background(.bar)
    }
}

/// The paragraph, folded away until somebody wants it.
///
/// Used on the questions where a reader may never have met the thing being
/// asked about: a $1,000 federal election, a 529, the order of operations on a
/// passport. **Not** used to hide something the reader needs in order to answer
/// the question in front of them, which is what it had become: the intake grew
/// one of these on every screen, including the state-of-birth question, and a
/// disclosure on every screen is just a page nobody reads with an extra tap in
/// front of it. Short and load-bearing goes in the footer; long and optional
/// goes in here.
struct OnboardingDisclosure: View {
    let label: String
    let text: String
    /// Set on the pages that are not forms, where the row has no card under it.
    var boxed = false
    @State private var isOpen = false

    var body: some View {
        if boxed {
            group.planCard()
        } else {
            group
        }
    }

    private var group: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
        } label: {
            Label(label, systemImage: "questionmark.circle")
                .font(.subheadline)
        }
        .accessibilityHint(isOpen ? "Collapses the explanation" : "Expands the explanation")
    }
}

/// Centres its content on a screen it fits on, and scrolls on one it does not.
///
/// The welcome and finished screens are a short block of text with a pinned
/// button under them. Top-aligned in a `ScrollView` they left half a phone of
/// empty page below the words, which reads as a layout that ran out. Centred
/// with fixed spacers they truncated the product's whole promise to an ellipsis
/// at an accessibility text size, which is worse. `ViewThatFits` takes the
/// centred version when the content fits the screen and the scrolling one when
/// it does not, and neither case needs a `GeometryReader`.
struct CentredIfItFits<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            ScrollView {
                content
                    .padding(.top, AppTheme.looseSpacing)
                    .padding(.bottom, AppTheme.spacing)
            }
        }
    }
}

/// Where you are in the intake. Ten screens without this reads as an unbounded
/// form; with it, it reads as a short one you are most of the way through.
struct StepDots: View {
    let current: OnboardingFlow.Step

    private var steps: [OnboardingFlow.Step] {
        OnboardingFlow.Step.allCases.filter { $0 != .welcome && $0 != .done }
    }

    private var currentIndex: Int {
        (steps.firstIndex(of: current) ?? 0) + 1
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(steps, id: \.self) { step in
                Circle()
                    .fill(stepIndex(for: step) <= currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Question \(currentIndex) of \(steps.count)")
    }

    private func stepIndex(for step: OnboardingFlow.Step) -> Int {
        (steps.firstIndex(of: step) ?? 0) + 1
    }
}

#Preview {
    OnboardingFlow()
        .modelContainer(BabyModelStore.makeInMemoryContainer())
}
