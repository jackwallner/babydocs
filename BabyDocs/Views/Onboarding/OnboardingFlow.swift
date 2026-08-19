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
    @State private var isUSCitizen = false

    // Household
    @State private var residenceStateCode = ""
    // Neutral by default, all three of them. Each one changes which tasks are
    // generated, so a value the parent never chose is a plan the parent never
    // chose: "married" quietly decides a parentage question, and "already on the
    // record" quietly removes the task about getting there.
    @State private var parentage: ParentageSituation = .unknown
    @State private var secondParentOnRecord = false
    @State private var insuranceKind: InsuranceKind = .unknown
    @State private var marketplaceKind: MarketplaceKind = .unknown
    @State private var hasDependentCareFSA = false

    // The optional four. A question is not an answer, so each starts off until
    // the parent explicitly adds it to the plan.
    @State private var takingParentalLeave = false
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

                // Not "nothing leaves this phone", which the app then goes on to
                // contradict on purpose: sending the plan to the other parent is
                // a link full of these answers, and it is one of the best things
                // here. The claim worth making is the one that stays true, which
                // is that nothing goes anywhere on its own.
                //
                // The long form of it is a paragraph, and a paragraph of
                // qualified privacy language is the last thing a reader on the
                // first screen needs in front of the button. It unfurls.
                OnboardingDisclosure(
                    label: "What happens to my answers",
                    text: "No household-data account, and no copy of your answers anywhere but here. Your plan stays on this phone unless you choose to send it, and photographs of documents never travel at all. Purchases are handled separately by Apple and RevenueCat, which is the one thing that does leave: an anonymous ID and what you bought, never anything about your family.",
                    boxed: true
                )
                .padding(.top, AppTheme.tightSpacing)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            // The "two windows close fast" line used to live here as fine
            // print under a button, which is the worst place for it: it is
            // jargon, and it is on the one screen where nothing can be done
            // about it. The explanation now sits on the coverage question,
            // where it is the decision being made.
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
                    "Date of birth",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
            } header: {
                Text("Your baby")
            }

            Section {
                statePicker("State of birth", selection: $birthStateCode)
                countyPicker(stateCode: birthStateCode, selection: $birthCounty)
                Toggle("US citizen", isOn: $isUSCitizen)
            } header: {
                Text("Where the birth was registered")
            }

            Section {
                OnboardingDisclosure(
                    label: "Why these three",
                    text: """
                    The date of birth is what every deadline in the app counts \
                    from, so it is the one answer worth double-checking. The \
                    birth certificate is issued where the birth was registered \
                    rather than where you live now, and in many states a county \
                    office is faster than the state one, which is the only \
                    reason the county is asked for. Citizenship turns on exactly \
                    one task, a federal account for newborn citizens, explained \
                    in a moment: if you are not sure, leave it off until you \
                    have verified it.
                    """
                )
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Your baby")
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: !birthStateCode.isEmpty) { step = .household }
        }
    }

    // MARK: - Household

    private var householdStep: some View {
        Form {
            Section {
                locationButton
                statePicker("State you live in", selection: $residenceStateCode)
            } header: {
                Text("Where you live")
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
            }

            Section {
                OnboardingDisclosure(
                    label: "Why we ask",
                    text: parentageExplanation
                )
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Your household")
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: !residenceStateCode.isEmpty) { step = .coverage }
        }
    }

    private var parentageExplanation: String {
        let base = "Where you live decides the Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with. "
        switch parentage {
        case .unknown:
            return base + "Nothing on your plan needs the parents question except one task: establishing a second parent who is not automatically on the record. Leave it where it is and that task stays off, and you can turn it on later in your household answers without redoing anything."
        case .unmarriedBothParents where !secondParentOnRecord:
            return base + "In most states marriage puts the second parent on the record automatically and an unmarried second parent has to establish it deliberately. That is state law and legally significant: the app will show you the task and your state's own form, and it will not prepare or file anything for you."
        default:
            return base + "The parents question decides one task. In most states marriage puts the second parent on the record automatically and an unmarried second parent has to establish it deliberately."
        }
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
                Text(insuranceKind == .unknown
                     ? "\"Not sure yet\" does not block anything, and it does not invent a date either."
                     : "This sets the hardest date in the app.")
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
                }
            }

            Section {
                Toggle("We have a dependent care FSA", isOn: $hasDependentCareFSA)
            }

            Section {
                OnboardingDisclosure(
                    label: "Why this is the important one",
                    text: coverageExplanation
                )
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Coverage")
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: true) { step = .leave }
        }
    }

    private var coverageExplanation: String {
        var text = "Two deadlines in this app are real doors closing, and both of them are here. A job-based plan must let you add the baby for at least 30 days after the birth. The Marketplace is 60. Miss the window and you usually wait for open enrollment. If you are covered both ways, pick the job-based plan: it is the shorter one. "
        if insuranceKind == .unknown {
            text += "\"Not sure yet\" is a real answer and it does not block anything: your plan gets one task at the top telling you what to find out and why it is worth doing this fortnight, and the moment you set the answer the real deadline appears in its place. "
        }
        if insuranceKind == .marketplace {
            text += "The 60 days is the same whichever marketplace you use. The site is not: some states run their own, with their own account and their own documents, and if you are not sure the task sends you to the federal page that picks your state for you. "
        }
        text += "A dependent care FSA is a separate election from the health plan, with its own window, and the one people most often miss because they assume the two move together. Your employer's plan document sets that window rather than the law, so Baby Docs shows it as a suggestion and asks you to confirm the real date."
        return text
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
            why: "It is a thousand dollars, most US citizen newborns can qualify, and almost nobody has heard of it. It is claimed by election rather than automatically, so a family that does not know about it simply does not get it. The election needs the baby's Social Security number first, which is why that task sits at the top of your plan.",
            adds: "A task that waits for the SSN, then points at the IRS page and the current form instructions. Baby Docs cannot tell you whether you qualify: there are conditions beyond citizenship and a birth year, and the instructions are the only thing that settles them.",
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

    private var canOfferReminders: Bool {
        !DeadlineReminderScheduler.plans(for: allTasks()).isEmpty
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
                OnboardingDisclosure(label: "Why it might matter to you", text: why)
                OnboardingDisclosure(label: "What it adds to your plan", text: adds)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(enabled: true, action: onContinue)
        }
    }
}

// MARK: - The two shapes every question shares

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
                    .foregroundStyle(.secondary)
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
/// Every question in this intake carries an explanation that is worth reading
/// once and is in the way every other time. As a form footer it was neither: it
/// pushed the controls off the screen for the reader who already knew, and it
/// still read as fine print to the reader who did not. Collapsed, the question
/// fits on one screen and the explanation is one tap away and phrased as an
/// invitation rather than as small grey text under a switch.
struct OnboardingDisclosure: View {
    let label: String
    let text: String
    /// Set on the two pages that are not forms. Inside a `Form` the row already
    /// has a card under it; on the welcome screen it had nothing, so a blue
    /// label and a chevron floated on the page looking like a mistake.
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
