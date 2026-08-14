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
                    Text("They tap the link and their phone builds the same plan: the same tasks, the same dates, their own reminders. It carries your answers and nothing else, so their copy starts blank on who has done what.")
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
                        Text("Nothing here is uploaded. The link carries your answers between two phones, and Baby Docs has no server to keep a copy on.")
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
            .planPageBackground()
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

                Section {
                    Button {
                        apply()
                    } label: {
                        Label(
                            children.isEmpty ? "Build my plan from this" : "Add this child to my plan",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                } footer: {
                    Text(children.isEmpty
                         ? "Your phone will run the same rules and produce the same deadlines."
                         : "Your household answers are replaced with the ones above, which rebuilds every child's plan on this phone.")
                }
            }
            .listStyle(.insetGrouped)
            .planPageBackground()
            .navigationTitle("A plan was shared with you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
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
        profile.hasDependentCareFSA = seed.hasDependentCareFSA
        profile.wantsPassport = seed.wantsPassport
        profile.wants529 = seed.wants529
        profile.wantsNewbornAccount = seed.wantsNewbornAccount
        profile.takingParentalLeave = seed.takingParentalLeave
        profile.recordLocalChange(in: context)

        // Matched on birth date and state rather than on name, because the name
        // is frequently still empty when the first parent sends the link and a
        // second row for the same baby is the one outcome worth working to
        // avoid.
        let existing = children.first {
            Calendar.current.isDate($0.birthDate, inSameDayAs: seed.birthDate)
                && $0.birthStateCode == seed.birthStateCode
        }
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
