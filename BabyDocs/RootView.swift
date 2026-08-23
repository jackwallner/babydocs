import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }) private var children: [Child]
    @Query(filter: #Predicate<Child> { $0.deletedAt != nil && !$0.isEphemeralDraft }, sort: \Child.birthDate)
    private var archivedChildren: [Child]

    @State private var navigator = AppNavigator.shared
    @State private var selectedTab: AppNavigator.Tab
    @State private var saveFailures = SaveFailureReporter.shared
    @State private var recoveredStoreURL: URL?
    @State private var hasAcknowledgedRecovery = false
    /// One ask per launch at most, whatever else happens.
    @State private var hasRequestedReviewThisSession = false
    /// Set by the intake's own last page. Nil until the intake has been on
    /// screen, so a launch with a plan already in the store never opens it.
    @State private var hasFinishedIntake = true
    @Environment(\.requestReview) private var requestReview

    init() {
        _selectedTab = State(initialValue: AppNavigator.shared.selectedTab)
    }

    var body: some View {
        Group {
            if let recoveredStoreURL, !hasAcknowledgedRecovery {
                StorageRecoveryView(location: recoveredStoreURL.lastPathComponent) {
                    hasAcknowledgedRecovery = true
                }
            } else if isIntakeOpen {
                // No child means no plan, and a plan is the entire app. The
                // intake is not a wizard the user can be dropped into the
                // middle of: every deadline in the app is derived from the
                // birth date and the state, so there is nothing to show until
                // those exist.
                //
                // **It stays open until the intake says it is finished**, which
                // it did not used to. The last two screens are inserted the
                // moment the first child exists, and this view swapped itself
                // for the tab bar in the same instant that child was written:
                // the plan-is-ready page and the one prompt for notification
                // permission were drawn for a fraction of a frame and never
                // seen by anybody. An intake that cannot show its own last page
                // cannot ask for the permission the whole product depends on.
                OnboardingFlow { hasFinishedIntake = true }
                    .onAppear { hasFinishedIntake = false }
            } else if children.isEmpty {
                ArchivedChildrenRecoveryView(children: archivedChildren)
            } else {
                TabView(selection: $selectedTab) {
                    PlanView()
                        .tabItem { Label("Plan", systemImage: "checklist") }
                        .tag(AppNavigator.Tab.plan)

                    ChildrenView()
                        .tabItem { Label("Children", systemImage: "figure.and.child.holdinghands") }
                        .tag(AppNavigator.Tab.children)

                    DocumentsView()
                        .tabItem { Label("Documents", systemImage: "folder") }
                        .tag(AppNavigator.Tab.documents)

                    // A permanent slot rather than a sheet nobody opens on
                    // purpose. Before Plus is bought it is the pitch; after, it
                    // is the timeline, the reminder switches and the pages that
                    // leave the phone, so the tab is worth its place in the bar
                    // to a customer who has already paid.
                    PlusView()
                        .tabItem { Label("Plus", systemImage: "sparkles") }
                        .tag(AppNavigator.Tab.plus)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppNavigator.Tab.settings)
                }
                // **Nothing is set on the tab bar on purpose.**
                //
                // It used to be forced visible and painted with the page
                // colour, which turns the system's floating glass capsule into
                // an opaque grey slab: the page then shows through as two black
                // gutters either side of it, which is the "black bars" in the
                // screenshots. Left alone, the bar is Liquid Glass, it takes its
                // own material from whatever scrolls under it, and there are no
                // gutters because there is no slab. `planPageBackground()` on
                // each tab is what gives the glass something to refract.
            }
        }
        .overlay {
            if scenePhase != .active {
                AppTheme.pageBackground
                    .ignoresSafeArea()
                    .overlay {
                        Text("Baby Docs")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            guard navigator.selectedTab != tab else { return }
            navigator.selectedTab = tab
        }
        .onChange(of: navigator.selectedTab) { _, tab in
            guard selectedTab != tab else { return }
            selectedTab = tab
        }
        .sheet(isPresented: $navigator.isShowingPaywall) {
            PaywallView()
        }
        .sheet(item: $navigator.pendingSeed) { seed in
            ImportPlanSheet(seed: seed) {
                navigator.selectedTab = .plan
            }
        }
        // A local-only app that swallows a failed write is telling the parent
        // their work is safe when it is not. This is the one place that says so,
        // wherever the write happened.
        .alert("That did not save", isPresented: saveFailureBinding) {
            Button("OK", role: .cancel) { saveFailures.clear() }
        } message: {
            Text(saveFailures.message ?? "")
        }
        .alert("That link did not work", isPresented: $navigator.seedFailed) {
            Button("OK", role: .cancel) { navigator.seedFailed = false }
        } message: {
            Text("Some message apps break long links. Ask the other parent to send it again, or answer the questions yourself: it takes about a minute.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .babyDocsDeadlineMet)) { _ in
            scheduleReviewRequestAfterDeadlineMet()
        }
        .task(id: children.count) {
            // Runs the catalog against whatever is in the store, at launch and
            // whenever a child is added. Cheap when nothing changed: the engine
            // writes only what actually moved.
            RequirementEngine.reconcileAll(in: context)
            await DeadlineReminderScheduler.reschedule(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                RequirementEngine.reconcileAll(in: context)
                Task {
                    await StoreService.shared.refresh()
                    await DeadlineReminderScheduler.reschedule(in: context)
                }
            case .inactive, .background:
                // Handing the phone to someone between two appointments should
                // not hand them the document vault as well.
                VaultStore.shared.lock()
            default:
                break
            }
        }
        .task {
            recoveredStoreURL = BabyModelStore.recoveredStoreURL
            purgeUnconfirmedChildDrafts()
            purgeTombstonedVaultDocuments()
            purgeOrphanedVaultPages()
        }
    }

    /// A process can die while the add-child sheet is open. Those rows are
    /// intentionally marked as scaffolding, so they must never become an
    /// archived child on the next launch.
    private func purgeUnconfirmedChildDrafts() {
        let descriptor = FetchDescriptor<Child>(predicate: #Predicate { $0.isEphemeralDraft })
        guard let drafts = try? context.fetch(descriptor), !drafts.isEmpty else { return }
        for draft in drafts {
            context.delete(draft)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            SaveFailureReporter.shared.report(error)
        }
    }

    /// A deletion can be interrupted between the model tombstone and the file
    /// cleanup. Keep the filenames on the tombstone until every file is gone,
    /// then retry on the next launch. This prevents sensitive photos becoming
    /// orphaned just because the phone was backgrounded at the wrong moment.
    private func purgeTombstonedVaultDocuments() {
        let descriptor = FetchDescriptor<VaultDocument>(
            predicate: #Predicate { $0.deletedAt != nil }
        )
        guard let documents = try? context.fetch(descriptor) else { return }
        for document in documents where !document.pageFileNames.isEmpty {
            let remaining = VaultStore.shared.removePages(named: document.pageFileNames)
            guard remaining != document.pageFileNames else { continue }
            document.pageFileNames = remaining
            document.recordLocalChange(in: context)
        }
    }

    /// A crash can leave a private image after the write but before its model
    /// row. Remove those files at launch so the vault never accumulates hidden
    /// copies that no screen can open.
    private func purgeOrphanedVaultPages() {
        let descriptor = FetchDescriptor<VaultDocument>()
        guard let documents = try? context.fetch(descriptor) else { return }
        let referenced = Set(documents.flatMap(\.pageFileNames))
        VaultStore.shared.removeOrphanedPages(referencedNames: referenced)
    }

    /// Whether the intake owns the screen.
    ///
    /// An empty store opens it, and it stays open until the intake's own last
    /// page says otherwise, even though the child it created is in the store by
    /// then. That gap is where the plan-is-ready page and the notification
    /// prompt live.
    private var isIntakeOpen: Bool {
        (children.isEmpty && archivedChildren.isEmpty) || !hasFinishedIntake
    }

    /// The system ask, one beat after the tick.
    ///
    /// `requestReview()` and nothing in front of it: no question about whether
    /// the app is helping, and no branch that decides who is allowed to reach
    /// the store. All this decides is the moment, which is the one thing the
    /// system API cannot know.
    ///
    /// Delayed rather than immediate because the row animates out of its bucket
    /// and into Done, and a sheet that lands on top of that reads as a
    /// consequence of the tap. Held back entirely while the paywall or an
    /// incoming plan link is on screen: those are the two places where an
    /// interruption costs something.
    private func scheduleReviewRequestAfterDeadlineMet() {
        guard eligibleToRequestReview else { return }

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard eligibleToRequestReview else { return }
            hasRequestedReviewThisSession = true
            ReviewPromptTracker.markRequested()
            requestReview()
        }
    }

    private var saveFailureBinding: Binding<Bool> {
        Binding(
            get: { saveFailures.message != nil },
            set: { if !$0 { saveFailures.clear() } }
        )
    }

    private var eligibleToRequestReview: Bool {
        !hasRequestedReviewThisSession
            && !navigator.isShowingPaywall
            && navigator.pendingSeed == nil
            && ReviewPromptTracker.shouldRequestAfterPositiveMoment()
    }

}

private struct StorageRecoveryView: View {
    let location: String
    let continueAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 42))
                        .foregroundStyle(.orange)
                    Text("Your saved plan needs attention")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Baby Docs could not open the file that contains your household answers and completed work. Nothing was deleted. The previous file is still on this phone as \(location).")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Before starting again, contact support so the saved plan can be checked. A new plan will not repair the old file.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Contact support", destination: URL(string: "https://jackwallner.com/ios/babydocs/support.html")!)
                        .buttonStyle(.borderedProminent)
                    Button("Set up a new plan anyway", action: continueAction)
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.margin)
            }
            .planPageBackground(underTabBar: false)
            .navigationTitle("Storage")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// `sheet(item:)` needs an identity, and a seed's identity is its contents: two
/// taps on the same link are the same sheet, and a different link is a different
/// one.
extension PlanSeed: Identifiable {
    var id: String { encoded() ?? "\(birthDate.timeIntervalSince1970)" }
}

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
}
