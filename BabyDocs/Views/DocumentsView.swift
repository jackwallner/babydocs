import PhotosUI
import SwiftData
import SwiftUI

/// The second question a parent actually asks.
///
/// The plan answers "what do I have to do". This answers "where is the thing
/// they are asking me for", which is the question at the counter, in the waiting
/// room and on the phone to a benefits administrator.
///
/// **Two jobs, and they are behind a switch rather than stacked.** The screen
/// used to run three sections down one list: what to find, what is in hand, and
/// a photo vault, each with its own header and its own footer, and every one of
/// them a different noun. Read from the top it looked like one list of documents
/// that had been shuffled, so nobody could tell that ticking a row and
/// photographing a certificate are unrelated actions. The switch names the two
/// jobs out loud: a checklist of what the tasks ask you to bring, and
/// photographs of the papers you already have.
struct DocumentsView: View {
    /// Which half of the screen is showing. Not a filter: two different jobs.
    enum Mode: String, CaseIterable, Identifiable {
        case checklist
        case copies

        var id: String { rawValue }

        var label: String {
            switch self {
            case .checklist: return "To bring"
            case .copies: return "Photos"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]

    @State private var vault = VaultStore.shared
    @State private var store = StoreService.shared
    @State private var navigator = AppNavigator.shared
    @State private var addingFor: Child?
    @State private var viewing: VaultDocument?
    @State private var errorMessage: String?
    /// A vault entry a swipe has proposed deleting, held until it is confirmed.
    /// See `confirmDelete`.
    @State private var pendingDeletion: VaultDocument?
    /// Ticked documents stay on screen. See `onHandSection`.
    @State private var isShowingOnHand = true
    @State private var mode: Mode = .checklist

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("What to show", selection: $mode) {
                        ForEach(Mode.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: 0, leading: 0, bottom: AppTheme.tightSpacing, trailing: 0
                    ))
                } footer: {
                    Text(modeFooter)
                }

                switch mode {
                case .checklist:
                    gatherSection
                    onHandSection
                case .copies:
                    ForEach(children) { child in
                        vaultSection(for: child)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .planPageBackground()
            .navigationTitle("Documents")
            // A checklist row is about a task, and until now it went nowhere:
            // the parent who wants to know *which* form the office wants, or
            // where the link to it is, had to leave and find the task by name.
            .navigationDestination(for: UUID.self) { id in
                if let task = liveTasks.first(where: { $0.id == id }) {
                    TaskDetailView(task: task)
                }
            }
            .sheet(item: $addingFor) { child in
                AddVaultDocumentSheet(child: child)
            }
            .sheet(item: $viewing) { document in
                VaultDocumentViewer(document: document)
            }
            // The one hard delete in the app, so it is the one that asks. A
            // swipe on a moving list is easy to do by accident, and the photos
            // go from disk immediately: there is no tombstone behind this and
            // nothing to swipe back.
            .confirmationDialog(
                pendingDeletion.map { "Delete \($0.displayTitle)?" } ?? "Delete this?",
                isPresented: deletionBinding,
                titleVisibility: .visible
            ) {
                Button("Delete the photos", role: .destructive) { confirmDelete() }
                Button("Keep them", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("The photos are removed from this phone now and cannot be recovered: they are not backed up anywhere. The document itself is unaffected.")
            }
            .alert("Could not remove all photos", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - What still has to be found

    private var liveTasks: [RequirementTask] {
        children.flatMap(\.liveTasks)
    }

    /// Every document every *open* task asks for, ticked or not. A task that is
    /// finished has stopped asking, so its list stops appearing here.
    private var checklist: [DocumentItem] {
        liveTasks.filter(\.isOpen).flatMap(\.liveDocuments)
    }

    private var gathered: [DocumentItem] {
        checklist.filter(\.isOnHand)
    }

    /// The identity a tick travels along: title **within one child**.
    ///
    /// It is what deduplicates a group, what collapses the in-hand list, and
    /// what makes ticking a certificate under one errand tick it under the other
    /// three that also want it.
    ///
    /// The child is half the identity, and leaving it out was a bug with real
    /// consequences: with two children the list collapsed to one "Birth
    /// certificate" row, ticking it marked the second baby's certificate as on
    /// hand too, and both the task detail and this screen then stopped asking
    /// for a document that did not exist. Twins are the worst case and also the
    /// likeliest one.
    private func identity(_ item: DocumentItem) -> String {
        let childID = item.task?.child?.id.uuidString ?? "unattached"
        return "\(childID)|\(item.title.lowercased())"
    }

    private func unique(_ items: [DocumentItem]) -> [DocumentItem] {
        var seen = Set<String>()
        return items.filter { seen.insert(identity($0)).inserted }
    }

    private var uniqueGathered: [DocumentItem] { unique(gathered) }

    /// **One group per task, soonest first, rather than one flat list.**
    ///
    /// Flat, this screen was forty-four rows of "Photo ID for the parent
    /// applying", "The per-copy fee", "Your benefits administrator's name"
    /// stacked in one column with nothing to say what any of them was for. Half
    /// of them are not even documents, they are things to have ready, and out of
    /// context they read as an inventory somebody else had made of a drawer.
    ///
    /// A parent is never gathering forty-four things. They are doing *one
    /// errand*, and the question is what to take to it, so the errand is the
    /// heading and its own deadline sits under it. A document wanted by four
    /// tasks appears under all four on purpose: it is needed at four counters,
    /// and ticking it in any one of them still ticks it in the rest.
    private var outstandingGroups: [(task: RequirementTask, items: [DocumentItem])] {
        TaskPlanner.sorted(liveTasks.filter(\.isOpen))
            .map { (task: $0, items: unique($0.liveDocuments.filter { !$0.isOnHand })) }
            .filter { !$0.items.isEmpty }
    }

    @ViewBuilder
    private var gatherSection: some View {
        let groups = outstandingGroups
        if groups.isEmpty {
            Section {
                Label("Everything your open tasks ask for is gathered.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } header: {
                PlanSectionHeader(title: "Still to find")
            }
        } else {
            ForEach(groups, id: \.task.id) { group in
                Section {
                    ForEach(group.items) { item in
                        DocumentChecklistRow(
                            item: item,
                            showChildName: false,
                            showTaskName: false,
                            onToggle: { setOnHand(item, true) }
                        )
                    }
                } header: {
                    PlanSectionHeader(
                        title: headerTitle(for: group.task),
                        blurb: TaskPlanner.duePhrase(for: group.task),
                        count: group.items.count
                    )
                }
            }
        }
    }

    private var modeFooter: String {
        switch mode {
        case .checklist:
            return children.count > 1
                ? "What to take to each errand. Tick something and it ticks on every task that wants it for that child, and never for the other child."
                : "What to take to each errand. Tick something and it ticks on every task that wants it."
        case .copies:
            return "Photographs of papers you already have. Nothing here is a task."
        }
    }

    /// The child's name leads once there is more than one, because with twins
    /// two groups are otherwise the same heading twice.
    private func headerTitle(for task: RequirementTask) -> String {
        guard children.count > 1, let name = task.child?.displayName else { return task.title }
        return "\(name) \u{00B7} \(task.title)"
    }

    /// **A ticked document does not vanish.**
    ///
    /// It used to: the only list on this screen was "still to find", so ticking
    /// the row was indistinguishable from deleting it. That is the worst
    /// possible feedback for the one gesture this screen exists for, because the
    /// question a parent asks at the counter is not "what is left" but "did I
    /// already deal with this one", and a list that answers only the first
    /// question makes them re-check the drawer.
    ///
    /// So it moves, visibly, into a list of what is in hand, and it can be
    /// unticked from there when the certificate turns out to be the
    /// informational copy after all.
    @ViewBuilder
    private var onHandSection: some View {
        let items = uniqueGathered
        if !items.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isShowingOnHand) {
                    ForEach(items) { item in
                        DocumentChecklistRow(
                            item: item,
                            showChildName: children.count > 1,
                            onToggle: { setOnHand(item, false) }
                        )
                    }
                } label: {
                    HStack(spacing: AppTheme.tightSpacing) {
                        Text("Already in hand")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 0)
                        Text("\(items.count)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Ticked, and deliberately still here: the question at the counter is \"did I already deal with this one\". Tap the tick to put one back on the list, or the row itself to open the task that asks for it.")
            }
        }
    }

    /// A document title appears on several of one child's tasks, so ticking it
    /// has to tick all of them. Anything else means a parent finds the
    /// certificate, ticks it, and the app keeps asking for it on three other
    /// screens.
    ///
    /// It stops at that child. One family's two birth certificates are two
    /// pieces of paper from two different orders, and one of them arriving tells
    /// you nothing about the other.
    private func setOnHand(_ item: DocumentItem, _ value: Bool) {
        let key = identity(item)
        for match in checklist where identity(match) == key {
            match.isOnHand = value
            match.markedOnHandAt = value ? Date() : nil
            match.recordLocalChange(in: context)
        }
    }

    // MARK: - The vault

    @ViewBuilder
    private func vaultSection(for child: Child) -> some View {
        let documents = child.liveVaultDocuments
        Section {
            if !vault.isUnlocked && !documents.isEmpty {
                Button {
                    Task { await vault.unlock() }
                } label: {
                    Label("\(documents.count) locked. Tap to unlock.", systemImage: "lock.fill")
                }
            } else {
                ForEach(documents) { document in
                    Button {
                        openViewer(document)
                    } label: {
                        HStack(spacing: AppTheme.spacing) {
                            Image(systemName: document.kind.symbol)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: AppTheme.hairSpacing) {
                                Text(document.displayTitle).foregroundStyle(.primary)
                                Text(pageLabel(document))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .pressableCard()
                }
                .onDelete { offsets in delete(offsets, from: documents) }

                addButton(for: child, existingCount: documents.count)
            }
        } header: {
            PlanSectionHeader(
                title: children.count > 1 ? "\(child.displayName)'s papers" : "Photos of your papers",
                blurb: documents.isEmpty
                    ? "So you are not driving home for the certificate."
                    : "",
                count: documents.isEmpty ? nil : documents.count
            )
        } footer: {
            Text(footerText(count: documents.count))
        }
    }

    @ViewBuilder
    private func addButton(for child: Child, existingCount: Int) -> some View {
        // Free during the weeks the paperwork is happening, and only then. The
        // vault is the strongest thing Plus has, and putting a wall in front of
        // it at the moment a parent is most stressed sells nothing and annoys
        // everyone. It starts asking once the intense period is over, which is
        // also when a parent has seen it work.
        if store.isPro || isWithinFreeWindow(child) {
            Button {
                Task {
                    guard await vault.unlock(reason: "Unlock the document vault") else { return }
                    addingFor = child
                }
            } label: {
                Label("Add a document", systemImage: "photo.badge.plus")
            }
        } else {
            Button {
                navigator.requestUpgrade()
            } label: {
                HStack {
                    Label("Add a document", systemImage: "photo.badge.plus")
                    Spacer(minLength: AppTheme.tightSpacing)
                    PlusBadge()
                }
            }
        }
    }

    /// The first twelve weeks after a birth, which is the window the whole app
    /// is built around. Adding is free inside it.
    private func isWithinFreeWindow(_ child: Child) -> Bool {
        child.ageInDays <= 84
    }

    private func footerText(count: Int) -> String {
        if count == 0 {
            return "They stay on this phone: not backed up, not uploaded, and Baby Docs has no server to put them on."
        }
        return "On this phone only. Not backed up, not uploaded. If you lose the phone these copies go with it, so keep the originals where you always kept them."
    }

    private func pageLabel(_ document: VaultDocument) -> String {
        let pages = document.pageCount == 1 ? "1 photo" : "\(document.pageCount) photos"
        return "\(pages) \u{00B7} added \(document.addedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func openViewer(_ document: VaultDocument) {
        Task {
            guard await vault.unlock(reason: "Unlock \(document.displayTitle)") else { return }
            viewing = document
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    /// A swipe proposes; the dialog decides. Nothing is removed here.
    private func delete(_ offsets: IndexSet, from documents: [VaultDocument]) {
        guard let index = offsets.first, documents.indices.contains(index) else { return }
        pendingDeletion = documents[index]
    }

    private func confirmDelete() {
        guard let document = pendingDeletion else { return }
        pendingDeletion = nil
        // The images go now, the row goes to a tombstone. A tombstone is what
        // makes an accidental swipe recoverable everywhere else in this app, but
        // leaving orphaned photographs of a Social Security card on disk after
        // someone asked for them to be gone is not a trade worth making.
        let remaining = VaultStore.shared.removePages(named: document.pageFileNames)
        document.pageFileNames = remaining
        if remaining.isEmpty {
            document.tombstone(in: context)
        } else {
            document.recordLocalChange(in: context)
            errorMessage = "Some photos could not be removed. The document is still listed so you can try again."
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

// MARK: - Adding

struct AddVaultDocumentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let child: Child

    @State private var kind: VaultDocumentKind = .birthCertificate
    @State private var customTitle = ""
    @State private var picked: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isShowingSensitiveNote = false
    @State private var hasAcknowledged = false
    @State private var isLoadingPhotos = false
    @State private var photoLoadError: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it") {
                    Picker("Document", selection: $kind) {
                        ForEach(VaultDocumentKind.allCases, id: \.self) { value in
                            Label(value.label, systemImage: value.symbol).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if kind == .other {
                        TextField("Name it", text: $customTitle)
                    }
                }

                Section {
                    photoPicker
                    if isLoadingPhotos {
                        ProgressView("Loading photos")
                    }
                    if let photoLoadError {
                        Text(photoLoadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.tightSpacing) {
                                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 96)
                                        .clipShape(AppTheme.innerShape)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Both sides, or every page. The photo is scaled down and saved as a copy; the one in your camera roll is untouched, and you may want to delete that one.")
                }
            }
            .navigationTitle("Add a document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: attemptSave)
                        .disabled(images.isEmpty || isLoadingPhotos)
                }
            }
            .onChange(of: picked) { _, items in
                Task { await load(items) }
            }
            .alert("Before you save this", isPresented: $isShowingSensitiveNote) {
                Button("I understand") {
                    hasAcknowledged = true
                    save()
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("This copy stays on this phone. It is not backed up and never leaves the device, so if you lose the phone the copy is gone. The card itself is still the record: keep it somewhere safe.")
            }
            .alert("Could not save", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// The title is read out into a local before the picker is built, because
    /// `PhotosPicker`'s label closure is `Sendable` and reaching into
    /// main-actor state from inside it is a strict-concurrency warning. A
    /// captured `String` is not.
    private var photoPicker: some View {
        let title = images.isEmpty ? "Choose photos" : "Choose different photos"
        return PhotosPicker(
            selection: $picked,
            maxSelectionCount: 8,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label(title, systemImage: "photo.on.rectangle")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func load(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        photoLoadError = nil
        var loaded: [UIImage] = []
        var failed = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            } else {
                failed += 1
            }
        }
        images = loaded
        isLoadingPhotos = false
        if failed > 0 {
            photoLoadError = failed == 1
                ? "One photo could not be loaded. Choose it again before saving."
                : "\(failed) photos could not be loaded. Choose them again before saving."
        }
    }

    /// The warning fires once per sensitive document rather than once per
    /// install. Someone photographing a Social Security card in month four has
    /// forgotten whatever an onboarding screen told them in week one, and this
    /// is the only moment the sentence is actually load-bearing.
    private func attemptSave() {
        if kind.isSensitive && !hasAcknowledged {
            isShowingSensitiveNote = true
        } else {
            save()
        }
    }

    private func save() {
        let document = VaultDocument(kind: kind, child: child)
        document.customTitle = customTitle
        var names: [String] = []
        var inserted = false
        do {
            for image in images {
                names.append(try VaultStore.shared.addPage(image))
            }
            document.pageFileNames = names
            context.insert(document)
            inserted = true
            guard document.recordLocalChange(in: context) else {
                if inserted { context.delete(document) }
                _ = VaultStore.shared.removePages(named: names)
                errorMessage = "Could not save the document. Nothing was kept. Try again after freeing some space."
                return
            }
            dismiss()
        } catch {
            if inserted { context.delete(document) }
            _ = VaultStore.shared.removePages(named: names)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Viewing

struct VaultDocumentViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let document: VaultDocument

    @State private var images: [UIImage] = []

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    EmptyStateView(
                        symbol: "photo",
                        title: "Nothing to show",
                        message: "The photos for this document could not be read."
                    )
                } else {
                    TabView {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            ZoomableImage(image: image)
                                .accessibilityLabel("Document photo \(index + 1) of \(images.count)")
                        }
                    }
                    .tabViewStyle(.page)
                    .background(Color.black)
                    .accessibilityLabel("Document pages")
                    .accessibilityHint("Swipe between pages. Pinch to zoom a page.")
                }
            }
            .navigationTitle(document.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Deliberately no share button, no save-to-photos, no print. There
            // is no way out of this screen that carries an image with it, which
            // is the only version of "it never leaves your phone" that is true
            // rather than aspirational.
        }
        .task {
            images = document.pageFileNames.compactMap { VaultStore.shared.image(named: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { images = [] }
        }
        .onDisappear { images = [] }
    }
}

/// Pinch and pan, because the thing a receptionist needs is usually a number in
/// eight-point type in one corner.
struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, min(6, $0.magnification)) }
                        .onEnded { _ in if scale <= 1.05 { reset() } },
                    DragGesture()
                        .onChanged { if scale > 1 { offset = $0.translation } }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { scale > 1 ? reset() : (scale = 3) }
            }
    }

    private func reset() {
        scale = 1
        offset = .zero
    }
}

#Preview {
    DocumentsView()
        .modelContainer(SampleData.previewContainer())
}
