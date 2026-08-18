import SwiftData
import SwiftUI

/// What replaced accounts, invitations and a sync backend.
///
/// The old version of this screen asked the other parent to make an account,
/// join a family and then stay in step with a server. This one sends them the
/// twelve answers their own phone needs to build the same plan, and is honest
/// that the two plans then run independently. That is a smaller promise, and it
/// is the one the app can actually keep.
struct SharePlanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let child: Child

    @State private var store = StoreService.shared

    private var seed: PlanSeed {
        PlanSeed.make(child: child, profile: FamilyProfileStore.current(in: context))
    }

    private var summary: String {
        PlanExporter.summary(for: child, profile: FamilyProfileStore.current(in: context))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let url = seed.shareURL() {
                        ShareLink(item: url, message: Text(messageBody)) {
                            Label("Send the plan", systemImage: "paperplane.fill")
                        }
                    }
                } header: {
                    Text("The other parent")
                } footer: {
                    Text("They tap the link and their phone builds the same plan: the same tasks, the same dates, their own reminders. Their copy starts blank on who has done what.\n\nThe link carries the answers that build a plan and nothing else: \(child.displayName)'s first name and date of birth, where the birth was registered, where you live, and your household answers. No completed tasks, no notes, no confirmation numbers and no photographs. Anyone the link is forwarded to can read it, so send it the way you would send a page of a form.")
                }

                Section {
                    SummaryShareControl(summary: { summary })
                } footer: {
                    Text("Plain text you can print, paste into a message or hand to whoever is driving to the appointment. It never includes the Social Security number.")
                }

                Section {
                    SummaryShareControl(
                        summary: {
                            PlanExporter.employerPacket(
                                for: child,
                                profile: FamilyProfileStore.current(in: context)
                            )
                        },
                        title: "Employer packet",
                        symbol: "briefcase"
                    )
                } header: {
                    Text("For work")
                } footer: {
                    Text("The qualifying-life-event page HR asks for: the event, the date, what you are enclosing and where the enrollment window comes from. The 30-day window is the hardest deadline in this app, and it is missed more often by sending something incomplete than by forgetting.")
                }

                Section {
                    Label {
                        Text("Nothing here is uploaded. The link carries your answers between two phones, and Baby Docs has no server to keep a copy on: the payload rides in the part of the address a browser never sends anywhere.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .planPageBackground(underTabBar: false)
            .navigationTitle("Send the plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var messageBody: String {
        """
        Here is our newborn paperwork plan. Open this on your phone and Baby Docs \
        will build the same list of deadlines for \(child.displayName).
        """
    }
}

/// What the other parent sees when they tap the link.
///
/// A confirmation, not an automatic import, and deliberately so. The link may
/// arrive weeks after they set the app up themselves, and silently replacing a
/// household's answers with a stranger's would be the single worst thing this
/// app could do. It says exactly what will change before it changes anything.
struct ImportPlanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }) private var children: [Child]

    let seed: PlanSeed
    var onImported: (() -> Void)?

    /// Which existing child this link is about, or nil for "add a new one".
    ///
    /// The import used to decide this itself, matching on birth date and birth
    /// state. Twins share both, so the first twin quietly took the second twin's
    /// name and the second was never added. Nothing here matches automatically
    /// any more: the app proposes and the recipient chooses.
    @State private var mergeTargetID: UUID?
    @State private var hasChosenTarget = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Baby", value: seed.name.isEmpty ? "Not named" : seed.name)
                    LabeledContent("Born", value: seed.birthDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Registered in", value: birthPlace)
                    LabeledContent("You live in", value: USState.displayName(for: seed.residenceStateCode))
                    LabeledContent("Coverage", value: InsuranceKind(rawValue: seed.insuranceKind)?.label ?? "Not set")
                } header: {
                    Text("What was sent")
                } footer: {
                    Text("These answers, and nothing else. No completed tasks, no documents and no photographs travel in a link.")
                }

                if !children.isEmpty {
                    Section {
                        Picker("This child is", selection: $mergeTargetID) {
                            Text("Someone new").tag(UUID?.none)
                            ForEach(children) { child in
                                Text("\(child.displayName), already on this phone").tag(UUID?.some(child.id))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Which child is this?")
                    } footer: {
                        Text(matchHint)
                    }
                }

                Section {
                    Button {
                        apply()
                    } label: {
                        Label(actionTitle, systemImage: "checkmark.circle.fill")
                    }
                } footer: {
                    Text(consequenceText)
                }
            }
            .listStyle(.insetGrouped)
            .planPageBackground(underTabBar: false)
            .navigationTitle("A plan was shared with you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .onAppear(perform: proposeTarget)
        }
    }

    /// Proposes the one obvious match and refuses to propose an ambiguous one.
    ///
    /// One child with the same birth date and birth state is almost certainly
    /// the same baby. Two are twins, and picking either is a coin flip that
    /// renames somebody's child, so the app proposes nothing and the picker
    /// starts on "Someone new".
    private func proposeTarget() {
        guard !hasChosenTarget else { return }
        hasChosenTarget = true
        let matches = children.filter {
            Calendar.current.isDate($0.birthDate, inSameDayAs: seed.birthDate)
                && $0.birthStateCode == seed.birthStateCode
        }
        mergeTargetID = matches.count == 1 ? matches[0].id : nil
    }

    private var mergeTarget: Child? {
        children.first { $0.id == mergeTargetID }
    }

    private var matchHint: String {
        if let target = mergeTarget {
            return "\(target.displayName) was born on the same day in the same state, so this link is probably about them. Choosing them updates that child's details rather than adding a second row for the same baby. If it is a different baby, pick \"Someone new\"."
        }
        return "Nothing on this phone obviously matches, so this will be added as another child. Twins share a birth date and a birth state, so Baby Docs will not guess between them."
    }

    private var actionTitle: String {
        if children.isEmpty { return "Build my plan from this" }
        if let target = mergeTarget { return "Replace my answers and update \(target.displayName)" }
        return "Replace my answers and add this child"
    }

    /// Says the whole effect, including the part the old label left out: this
    /// overwrites the household answers and regenerates every child's plan, not
    /// just the one in the link.
    private var consequenceText: String {
        if children.isEmpty {
            return "Your phone will run the same rules and produce the same deadlines."
        }
        let names = children.map(\.displayName).joined(separator: ", ")
        let affected = children.count == 1
            ? "\(names)'s plan is rebuilt from them"
            : "every child's plan is rebuilt from them: \(names)"
        return "The household answers above replace the ones on this phone, and \(affected). What you have already done is kept: completed tasks, notes, confirmations and your documents are untouched."
    }

    private var birthPlace: String {
        var parts: [String] = []
        if !seed.birthCounty.isEmpty { parts.append(seed.birthCounty) }
        if !seed.birthStateCode.isEmpty { parts.append(USState.displayName(for: seed.birthStateCode)) }
        return parts.isEmpty ? "Not set" : parts.joined(separator: ", ")
    }

    private func apply() {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = seed.residenceStateCode
        profile.parentageRaw = seed.parentage
        profile.secondParentOnRecord = seed.secondParentOnRecord
        profile.insuranceKindRaw = seed.insuranceKind
        profile.marketplaceKindRaw = seed.marketplaceKind ?? MarketplaceKind.unknown.rawValue
        profile.hasDependentCareFSA = seed.hasDependentCareFSA
        profile.wantsPassport = seed.wantsPassport
        profile.wants529 = seed.wants529
        profile.wantsNewbornAccount = seed.wantsNewbornAccount
        profile.takingParentalLeave = seed.takingParentalLeave
        profile.recordLocalChange(in: context)

        // Whichever child the recipient picked, and nothing inferred. See
        // `proposeTarget`.
        let existing = mergeTarget
        let child = existing ?? Child()
        child.name = seed.name
        child.birthDate = seed.birthDate
        child.birthStateCode = seed.birthStateCode
        child.birthCounty = seed.birthCounty
        child.isUSCitizen = seed.isUSCitizen
        if existing == nil {
            child.colorIndex = children.count
            context.insert(child)
        }
        child.recordLocalChange(in: context)

        RequirementEngine.reconcileAll(in: context)
        onImported?()
        dismiss()
    }
}
