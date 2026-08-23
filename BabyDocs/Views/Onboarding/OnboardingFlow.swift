import SwiftData
import SwiftUI
import UIKit

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
    /// Called by the last page. `RootView` keeps the intake on screen until
    /// this fires, which is what makes the last two pages reachable at all: the
    /// child exists in the store from `finish()` onward, and the root used to
    /// swap itself for the tab bar the instant it appeared.
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step = .welcome
    @State private var location = LocationLookup()

    // Baby
    @State private var name = ""
    @State private var birthDate = Date()
    @State private var birthDateConfirmed = false
    @State private var birthStateCode = ""
    @State private var birthCounty = ""
    @State private var isUSCitizen: Bool?

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
    @State private var parentageConfirmed = false
    @State private var secondParentOnRecord = false
    @State private var insuranceKind: InsuranceKind = .unknown
    @State private var coverageConfirmed = false
    @State private var marketplaceKind: MarketplaceKind = .unknown
    @State private var employerPlanName = ""
    @State private var benefitsContactNote = ""
    @State private var hasDependentCareFSA = false

    // The optional four. A question is not an answer, so each starts off until
    // the parent explicitly adds it to the plan.
    /// Nil until the parent picks, rather than defaulting to `.nobody`.
    ///
    /// A checkmark sitting on "Nobody is taking leave" before anybody touched
    /// the screen is an answer nobody gave, and it is the answer that removes
    /// the one piece of newborn paperwork that pays the family. The three
    /// options are all visible and Continue is one tap away once one is
    /// chosen, so nothing here is a dead end: "Nobody" is still an answer,
    /// it just has to be given.
    @State private var leaveTakers: ParentalLeaveTakers?
    @State private var wantsNewbornAccount = false
    @State private var wants529 = false
    @State private var wantsPassport = false

    @State private var result: RequirementEngine.Result?
    @State private var didLoadDraft = false
    /// One ask, and never a second one on the same page: iOS shows the system
    /// prompt once, so a button that stays put afterwards does nothing and
    /// reads as broken.
    @State private var hasAskedForReminders = false

    enum Step: Int, CaseIterable {
        case welcome, baby, household, coverage
        case leave, newbornAccount, plan529, passport
        case done, plus
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
                case .plus: plusStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome && step != .done && step != .plus {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { back() }
                    }
                    ToolbarItem(placement: .principal) {
                        StepDots(current: step)
                    }
                }
            }
            .onAppear(perform: restoreDraft)
            .onChange(of: draftSnapshot) { _, draft in
                guard didLoadDraft else { return }
                OnboardingDraftStore.save(draft)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                persistDraft()
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
            .padding(.horizontal, AppTheme.margin)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(title: "Get started", note: "About a minute. Nothing is submitted anywhere.") {
                step = .baby
            }
        }
    }

    // MARK: - Baby

    private var babyStep: some View {
        OnboardingStep(
            symbol: "figure.child",
            title: "Who is the plan for?",
            subtitle: "Every deadline counts from the date of birth, and the state that registered it issues the certificate.",
            navigationTitle: "Your baby",
            enabled: birthDateConfirmed && !birthStateCode.isEmpty && isUSCitizen != nil,
            note: babyContinueNote,
            onContinue: { step = .household }
        ) {
            Section {
                TextField("First name (optional)", text: $name)
                DatePicker(
                    selection: Binding(
                        get: { birthDate },
                        set: { newValue in
                            if !DateOnly.sameDay(newValue, birthDate) {
                                birthDateConfirmed = false
                            }
                            birthDate = newValue
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                ) {
                    RequiredLabel("Date of birth")
                }
                Toggle("I checked this date", isOn: $birthDateConfirmed)
                    .accessibilityLabel("I checked this date")
            } header: {
                Text("Date of birth")
            } footer: {
                Text("The one answer worth double-checking, because every other date in the app is derived from it.")
            }

            Section {
                locationButton
                statePicker(
                    "State of birth",
                    selection: Binding(
                        get: { birthStateCode },
                        set: { newValue in
                            if newValue != birthStateCode {
                                birthCounty = ""
                            }
                            birthStateCode = newValue
                        }
                    ),
                    required: true
                )
                countyPicker(stateCode: birthStateCode, selection: $birthCounty)
            } header: {
                Text("Where the birth was registered")
            } footer: {
                Text(birthFooter)
            }

            // Its own section, and a header that says what the two rows are.
            // Two bare options reading "US citizen" and "Not a US citizen" under
            // a heading about where the birth was registered is a question with
            // no question on it.
            Section {
                OnboardingOptionRow(label: "US citizen", isSelected: isUSCitizen == true) {
                    isUSCitizen = true
                }
                OnboardingOptionRow(label: "Not a US citizen", isSelected: isUSCitizen == false) {
                    isUSCitizen = false
                }
            } header: {
                RequiredLabel("Citizenship")
            } footer: {
                Text("Only one rule turns on this: the $1,000 federal newborn account is for US citizen children.")
            }
        }
    }

    private var babyContinueNote: String {
        if !birthDateConfirmed { return "Check the date of birth to carry on." }
        if birthStateCode.isEmpty { return "Pick the state of birth to carry on." }
        if isUSCitizen == nil { return "Choose the baby's citizenship to carry on." }
        return ""
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
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: AppTheme.spacing) {
                    Button("Try again") {
                        location.reset()
                        Task { await location.find() }
                    }
                    if location.isDenied {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .font(.footnote.weight(.medium))
            }
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
        OnboardingStep(
            symbol: "house",
            title: "Where do you live, and who is on the record?",
            subtitle: "Where you live helps route the agency. Leave rules also depend on the employer and the state where that parent works. Who is on the record decides one legally significant task.",
            navigationTitle: "Your household",
            enabled: !residenceStateCode.isEmpty && parentageConfirmed,
            note: householdContinueNote,
            onContinue: { step = .coverage }
        ) {
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
                ForEach(ParentageSituation.allCases, id: \.self) { value in
                    OnboardingOptionRow(
                        label: value.label,
                        isSelected: parentageConfirmed && parentage == value
                    ) {
                        parentage = value
                        parentageConfirmed = true
                        if value != .unmarriedBothParents {
                            secondParentOnRecord = false
                        }
                    }
                }

                if parentage == .unmarriedBothParents {
                    Toggle("Both parents already on the birth record", isOn: $secondParentOnRecord)
                }
            } header: {
                Text("Parents")
            } footer: {
                Text(parentageFooter)
            }
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
            return "A neutral task will remind you to ask the birth registrar whether parentage paperwork applies. Baby Docs will not assume a legal situation or tell you to sign a form."
        case .unmarriedBothParents where !secondParentOnRecord:
            return "In most states marriage puts the second parent on the record automatically and an unmarried second parent has to establish it deliberately. Your plan will carry that task and your state's own form. Baby Docs will not prepare or file it for you."
        default:
            return "This decides one task: in most states marriage puts the second parent on the record automatically, and an unmarried second parent has to establish it deliberately."
        }
    }

    private var householdContinueNote: String {
        if residenceStateCode.isEmpty { return "Pick the state you live in to carry on." }
        if !parentageConfirmed { return "Choose the parents' situation, including Prefer not to say, to carry on." }
        return ""
    }

    // MARK: - Coverage

    private var coverageStep: some View {
        OnboardingStep(
            symbol: "cross.case",
            title: "How is the family covered?",
            subtitle: "This sets the only two dates in the app that legally close.",
            navigationTitle: "Coverage",
            enabled: coverageConfirmed,
            note: coverageConfirmed ? "" : "Choose a coverage answer, including Not sure yet, to carry on.",
            onContinue: { step = .leave }
        ) {
            Section {
                ForEach(InsuranceKind.allCases, id: \.self) { value in
                    OnboardingOptionRow(
                        label: value.label,
                        isSelected: coverageConfirmed && insuranceKind == value
                    ) {
                        insuranceKind = value
                        coverageConfirmed = true
                        if value != .marketplace { marketplaceKind = .unknown }
                        if value != .employer {
                            employerPlanName = ""
                            benefitsContactNote = ""
                        }
                    }
                }
            } header: {
                Text("Where the coverage comes from")
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
                    ForEach(MarketplaceKind.allCases, id: \.self) { value in
                        OnboardingOptionRow(
                            label: value.label,
                            isSelected: marketplaceKind == value
                        ) {
                            marketplaceKind = value
                        }
                    }
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
        OnboardingStep(
            symbol: "briefcase",
            title: "Who is taking parental leave?",
            subtitle: "Paid or unpaid time off after the birth, from an employer, a state programme, or federal job protection.",
            navigationTitle: "Leave",
            enabled: leaveTakers != nil,
            note: leaveTakers == nil ? "Pick one to carry on. \"Nobody\" is a real answer here." : "",
            onContinue: { step = isUSCitizen == true ? .newbornAccount : .plan529 }
        ) {
            Section {
                ForEach(ParentalLeaveTakers.allCases, id: \.self) { value in
                    OnboardingOptionRow(label: value.label, isSelected: leaveTakers == value) {
                        leaveTakers = value
                    }
                }
            } header: {
                Text("Parental leave")
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
    }

    private var leaveFooter: String {
        switch leaveTakers {
        case .none:
            return "Nothing is selected yet. Pick one and this will say what it puts on the plan."
        case .some(.nobody):
            return "Nothing about leave goes on your plan. You can change this later without redoing any of this."
        case .some(.oneParent):
            return "One task, with your state's own programme, the federal rules behind it, and what the employer needs from you."
        case .some(.bothParents):
            return "Two tasks, one for each parent. Each claim goes to a different employer, and the rules for a second parent's bonding leave are often not the rules for the birth parent's."
        }
    }

    private var newbornAccountStep: some View {
        ExplainedChoice(
            symbol: "dollarsign.circle",
            title: "Claim the $1,000 newborn account?",
            navigationTitle: "Newborn account",
            what: "A one-time $1,000 federal contribution into an investment account for children born between 2025 and 2028. The IRS calls these Trump Accounts, which is the name you will see on irs.gov and on the form itself.",
            detailLabel: "Why almost nobody claims this",
            detail: "It is a thousand dollars, most US citizen newborns can qualify, and it is claimed by election rather than automatically, so a family that has not heard of it simply does not get it. The election needs the baby's Social Security number first, which is why that task sits at the top of your plan. Baby Docs cannot tell you whether you qualify: there are conditions beyond citizenship and a birth year, and the instructions are the only thing that settles them.",
            isOn: $wantsNewbornAccount,
            toggleLabel: "Add this to my plan",
            isAvailable: isUSCitizen == true,
            unavailableNote: "This one is for US citizen children only, and you said this baby is not one, so it stays off your plan."
        ) { step = .plan529 }
    }

    private var plan529Step: some View {
        ExplainedChoice(
            symbol: "graduationcap",
            title: "Open a 529?",
            navigationTitle: "529",
            what: "A tax-advantaged savings account for education. Most states run their own, several give residents a state tax deduction for paying into it, and you can use another state's if theirs is better.",
            detailLabel: "Why now rather than in a year",
            detail: "Nothing about a 529 is urgent, and this app will not pretend otherwise: there is no deadline and no penalty for opening one next year. It is here because it is far easier to do in the same fortnight you are already gathering a birth certificate and a Social Security number than it is to come back to in eighteen months. Saying yes adds one unhurried task with your state's own plan and what opening an account asks for.",
            isOn: $wants529,
            toggleLabel: "Add this to my plan"
        ) { step = .passport }
    }

    private var passportStep: some View {
        ExplainedChoice(
            symbol: "airplane",
            title: "Will the baby need a passport?",
            navigationTitle: "Passport",
            what: "A US passport for a child under 16. Both parents have to appear in person with the child, or the absent one has to send a notarised consent form.",
            detailLabel: "Why this one has to start earliest",
            detail: "The application needs a certified birth certificate, so it cannot start until that has arrived, and the in-person rule is what catches people out. If there is a trip in the first year, this is the task that has to be started earliest and is almost always started last. It stays blocked on your plan until the certificate is in hand, then explains the appointment and who has to be at it.",
            isOn: $wantsPassport,
            toggleLabel: "Add this to my plan"
        ) { finish() }
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
            .padding(.horizontal, AppTheme.margin)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: AppTheme.tightSpacing) {
                if canOfferReminders && !hasAskedForReminders {
                    Button {
                        Task {
                            // Asked here, and only here, because this is the first
                            // moment there is a real closing window to be reminded
                            // about. Asked on launch it reads as noise and gets
                            // refused permanently, and a refused prompt is the one
                            // thing the app cannot undo.
                            hasAskedForReminders = true
                            await NotificationService.shared.requestAuthorization()
                            await DeadlineReminderScheduler.reschedule(for: allTasks())
                        }
                    } label: {
                        Text("Remind me before deadlines").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("Two dates in your plan legally close. This is how the app tells you before they do, and it is free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Prominent unless the reminder ask is still on screen above
                // it, where two filled buttons stacked would give a parent no
                // idea which one the page wants.
                if canOfferReminders && !hasAskedForReminders {
                    Button { step = .plus } label: {
                        Text("See my plan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button { step = .plus } label: {
                        Text("See my plan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, AppTheme.margin)
            .padding(.top, AppTheme.spacing)
            .padding(.bottom, AppTheme.tightSpacing)
            .background(.bar)
        }
    }

    // MARK: - Plus

    /// The offer, once, at the only moment it can be honest.
    ///
    /// It comes *after* the plan is built rather than before the questions,
    /// because a pitch in front of an empty app is selling a promise instead of
    /// a thing. By this page the parent has seen how many tasks apply to their
    /// household, which is the whole argument for wanting the order and the
    /// reminders, and skipping costs one tap and loses nothing they were shown.
    private var plusStep: some View {
        PlusPurchaseView(
            placement: .onboarding,
            onPurchased: { onFinish() },
            onSkip: { onFinish() }
        )
        .navigationTitle("Baby Docs Plus")
        .navigationBarTitleDisplayMode(.inline)
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
        if previous == .newbornAccount && isUSCitizen != true {
            previous = .leave
        }
        step = previous
    }

    private func finish() {
        guard let isUSCitizen else { return }
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = residenceStateCode
        profile.parentage = parentage
        profile.secondParentOnRecord = parentage == .unmarriedBothParents && secondParentOnRecord
        profile.insuranceKind = insuranceKind
        profile.marketplaceKind = insuranceKind == .marketplace ? marketplaceKind : .unknown
        profile.employerPlanName = insuranceKind == .employer ? employerPlanName : ""
        profile.benefitsContactNote = insuranceKind == .employer ? benefitsContactNote : ""
        profile.hasDependentCareFSA = hasDependentCareFSA
        profile.wantsPassport = wantsPassport
        profile.wants529 = wants529
        profile.wantsNewbornAccount = wantsNewbornAccount
        profile.parentalLeaveTakers = leaveTakers ?? .nobody
        profile.updatedAt = Date()

        let child = Child(name: name, birthDate: birthDate, birthStateCode: birthStateCode)
        child.birthCounty = birthCounty
        child.isUSCitizen = isUSCitizen
        context.insert(child)
        // The engine saves the pending profile, child and generated plan at one
        // boundary. A failed write leaves the intake open instead of showing a
        // success state for a plan that only partly reached disk.
        result = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        guard result?.didPersist == true else {
            return
        }

        OnboardingDraftStore.clear()
        // The one moment in the intake that is an outcome rather than a step:
        // ten questions in, there is now a plan. Every Continue before this is
        // silent, which is what leaves this one meaning something.
        Haptics.completed()
        step = .done
    }

    private var draftSnapshot: OnboardingDraft {
        OnboardingDraft(
            step: step.rawValue,
            name: name,
            birthDate: DateOnly.canonical(birthDate),
            birthDateConfirmed: birthDateConfirmed,
            birthStateCode: birthStateCode,
            birthCounty: birthCounty,
            isUSCitizen: isUSCitizen,
            residenceStateCode: residenceStateCode,
            parentage: parentage.rawValue,
            parentageConfirmed: parentageConfirmed,
            secondParentOnRecord: secondParentOnRecord,
            insuranceKind: insuranceKind.rawValue,
            coverageConfirmed: coverageConfirmed,
            marketplaceKind: marketplaceKind.rawValue,
            employerPlanName: PlanSeed.safeExternalText(employerPlanName),
            benefitsContactNote: PlanSeed.safeExternalText(benefitsContactNote),
            hasDependentCareFSA: hasDependentCareFSA,
            leaveTakers: leaveTakers?.rawValue,
            wantsNewbornAccount: wantsNewbornAccount,
            wants529: wants529,
            wantsPassport: wantsPassport
        )
    }

    private func persistDraft() {
        guard didLoadDraft, step != .done, step != .plus else { return }
        OnboardingDraftStore.save(draftSnapshot)
    }

    private func restoreDraft() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        if ProcessInfo.processInfo.arguments.contains("-uitest-wipe-store") {
            OnboardingDraftStore.clear()
            return
        }
        guard let draft = OnboardingDraftStore.load(),
              let restoredStep = Step(rawValue: draft.step),
              restoredStep != .done, restoredStep != .plus else { return }
        step = restoredStep
        name = draft.name
        birthDate = DateOnly.canonicalFromUTC(draft.birthDate)
        birthDateConfirmed = draft.birthDateConfirmed ?? false
        birthStateCode = draft.birthStateCode
        birthCounty = draft.birthCounty
        isUSCitizen = draft.isUSCitizen
        residenceStateCode = draft.residenceStateCode
        parentage = ParentageSituation(rawValue: draft.parentage) ?? .unknown
        parentageConfirmed = draft.parentageConfirmed ?? (parentage != .unknown)
        secondParentOnRecord = draft.secondParentOnRecord
        insuranceKind = InsuranceKind(rawValue: draft.insuranceKind) ?? .unknown
        coverageConfirmed = draft.coverageConfirmed ?? (insuranceKind != .unknown)
        marketplaceKind = MarketplaceKind(rawValue: draft.marketplaceKind) ?? .unknown
        employerPlanName = draft.employerPlanName
        benefitsContactNote = draft.benefitsContactNote
        hasDependentCareFSA = draft.hasDependentCareFSA
        leaveTakers = draft.leaveTakers.flatMap(ParentalLeaveTakers.init(rawValue:))
        wantsNewbornAccount = draft.wantsNewbornAccount
        wants529 = draft.wants529
        wantsPassport = draft.wantsPassport
    }

    private func allTasks() -> [RequirementTask] {
        ((try? context.fetch(FetchDescriptor<Child>())) ?? [])
            .filter { $0.deletedAt == nil && !$0.isEphemeralDraft }
            .flatMap(\.liveTasks)
    }

    private var canOfferReminders: Bool {
        !DeadlineReminderScheduler.plans(for: allTasks()).isEmpty
    }
}

struct OnboardingDraft: Codable, Equatable {
    var version = 1
    var savedAt: Date? = Date()
    var step: Int
    var name: String
    var birthDate: Date
    var birthDateConfirmed: Bool?
    var birthStateCode: String
    var birthCounty: String
    var isUSCitizen: Bool?
    var residenceStateCode: String
    var parentage: String
    var parentageConfirmed: Bool?
    var secondParentOnRecord: Bool
    var insuranceKind: String
    var coverageConfirmed: Bool?
    var marketplaceKind: String
    var employerPlanName: String
    var benefitsContactNote: String
    var hasDependentCareFSA: Bool
    var leaveTakers: String?
    var wantsNewbornAccount: Bool
    var wants529: Bool
    var wantsPassport: Bool
}

enum OnboardingDraftStore {
    private static let key = "babydocs.onboarding-draft"
    private static let retention: TimeInterval = 7 * 24 * 60 * 60

    static func load() -> OnboardingDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard var draft = try? JSONDecoder().decode(OnboardingDraft.self, from: data),
              let savedAt = draft.savedAt,
              Date().timeIntervalSince(savedAt) <= retention
        else {
            clear()
            return nil
        }
        let sanitized = draft.sanitized
        if sanitized != draft {
            save(sanitized)
            draft = sanitized
        }
        return draft
    }

    static func save(_ draft: OnboardingDraft) {
        guard let data = try? JSONEncoder().encode(draft.sanitized) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private extension OnboardingDraft {
    var sanitized: OnboardingDraft {
        var copy = self
        copy.name = PlanSeed.safeExternalText(name)
        copy.birthCounty = PlanSeed.safeExternalText(birthCounty)
        copy.employerPlanName = PlanSeed.safeExternalText(employerPlanName)
        copy.benefitsContactNote = PlanSeed.safeExternalText(benefitsContactNote)
        return copy
    }
}


/// One answer, in a row, ticked only once somebody has actually chosen it.
///
/// The intake had two ways of asking the same kind of question. The leave page
/// used buttons with nothing selected until a parent picked; the coverage,
/// parentage and citizenship pages used an inline `Picker`, which draws a
/// checkmark against whatever the model happens to hold. On a screen whose
/// Continue button then refuses to work, that tick is the worst possible thing
/// to show: it says an answer has been given, next to a button that says one
/// has not, and the answer it claims is "not sure", which is the one that
/// changes what the plan does.
struct OnboardingOptionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else { return }
            action()
            Haptics.selected()
        } label: {
            HStack {
                Text(label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppTheme.tightSpacing)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .pressableCard()
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    /// The nav bar's own short label. A full question truncates to nothing
    /// useful up there.
    let navigationTitle: String
    let what: String
    let detailLabel: String
    let detail: String
    @Binding var isOn: Bool
    let toggleLabel: String
    var isAvailable: Bool = true
    var unavailableNote: String = ""
    let onContinue: () -> Void

    var body: some View {
        OnboardingStep(
            symbol: symbol,
            title: title,
            subtitle: what,
            navigationTitle: navigationTitle,
            enabled: true,
            note: "",
            onContinue: onContinue
        ) {
            Section {
                if isAvailable {
                    Toggle(toggleLabel, isOn: $isOn)
                } else {
                    Text(unavailableNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Your answer")
            } footer: {
                Text("You can change this later in the household answers without redoing any of this.")
            }

            Section {
                OnboardingDisclosure(label: detailLabel, text: detail)
            }
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
        HStack(spacing: AppTheme.hairSpacing) {
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

            // **The note's space is reserved whether or not there is a note.**
            //
            // It used to appear and disappear with the answer, which moved the
            // Continue button up and down by two lines *within a single
            // question*, and moved it to a different height on every question in
            // the intake. Nothing in that motion is information: the button did
            // not change, the page did not change, and a control that will not
            // hold still is read as an unfinished app. Two footnote lines are
            // held open here, and a longer note grows the block rather than
            // being truncated.
            ZStack {
                // Two footnote lines of height and nothing else: hidden from
                // VoiceOver as well as from the eye, because a blank string
                // read out under the only button on the page is worse than the
                // jump it exists to prevent.
                Text(" \n ")
                    .font(.footnote)
                    .hidden()
                    .accessibilityHidden(true)
                if !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(enabled ? .secondary : Color.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, AppTheme.margin)
        .padding(.top, AppTheme.spacing)
        .padding(.bottom, AppTheme.tightSpacing)
        .background(.bar)
    }
}

/// The top of every question, in the same place, at the same size.
///
/// The intake had two page shapes: half the questions opened with an icon, a
/// bold question and a line of explanation, and half opened straight into a form
/// section header. Flipping between them moved the first row of the form by
/// about eighty points, question to question, so the whole intake read as a
/// series of unrelated screens rather than one thing being filled in. What
/// should move between two questions is the words and the glyph. Nothing else.
struct OnboardingHero: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.tightSpacing)
    }
}

/// One question: hero, form, pinned footer. Every step in the intake is one of
/// these, which is the only way the shape stays the same as the questions
/// change.
struct OnboardingStep<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    let navigationTitle: String
    var continueTitle = "Continue"
    var enabled = true
    var note = ""
    let onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                OnboardingHero(symbol: symbol, title: title, subtitle: subtitle)
            }
            .listRowBackground(Color.clear)

            content
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            OnboardingFooter(
                title: continueTitle,
                enabled: enabled,
                note: note,
                action: onContinue
            )
        }
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
                .padding(.vertical, AppTheme.hairSpacing)
        } label: {
            Label(label, systemImage: "questionmark.circle")
                .font(.subheadline)
        }
        .accessibilityHint(isOpen ? "Collapses the explanation" : "Expands the explanation")
    }
}

/// Keeps short content pleasant while guaranteeing a scroll path at every text size.
///
/// The welcome and finished screens are a short block of text with a pinned
/// button under them. Top-aligned in a `ScrollView` they left half a phone of
/// empty page below the words, which reads as a layout that ran out. Centred
/// with fixed spacers they truncated the product's whole promise to an ellipsis
/// at an accessibility text size, which is worse. The old `ViewThatFits`
/// approach could choose the centred stack before the safe-area inset and text
/// size had been accounted for. A scroll view is slightly less decorative on a
/// short screen, but it never clips the promise or hides the only way forward.
struct CentredIfItFits<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.top, AppTheme.looseSpacing)
                .padding(.bottom, AppTheme.spacing)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Where you are in the intake. Ten screens without this reads as an unbounded
/// form; with it, it reads as a short one you are most of the way through.
struct StepDots: View {
    let current: OnboardingFlow.Step

    private var steps: [OnboardingFlow.Step] {
        OnboardingFlow.Step.allCases.filter { $0 != .welcome && $0 != .done && $0 != .plus }
    }

    private var currentIndex: Int {
        (steps.firstIndex(of: current) ?? 0) + 1
    }

    var body: some View {
        HStack(spacing: AppTheme.hairSpacing) {
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
