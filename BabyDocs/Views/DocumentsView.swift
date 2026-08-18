import PhotosUI
import SwiftData
import SwiftUI

/// The second question a parent actually asks.
///
/// The plan answers "what do I have to do". This answers "where is the thing
/// they are asking me for", which is the question at the counter, in the waiting
/// room and on the phone to a benefits administrator. It is two lists that
/// belong together: what still has to be found, gathered across every task so
/// nobody has to open fifteen screens to build one errand, and copies of what
/// has already been found.
struct DocumentsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Child> { $0.deletedAt == nil }, sort: \Child.birthDate)
    private var children: [Child]

    @State private var vault = VaultStore.shared
    @State private var store = StoreService.shared
    @State private var navigator = AppNavigator.shared
    @State private var addingFor: Child?
    @State private var viewing: VaultDocument?
    /// A vault entry a swipe has proposed deleting, held until it is confirmed.
    /// See `confirmDelete`.
    @State private var pendingDeletion: VaultDocument?

    var body: some View {
        NavigationStack {
            List {
                gatherSection

                ForEach(children) { child in
                    vaultSection(for: child)
                }
            }
            .listStyle(.insetGrouped)
            .planPageBackground()
            .navigationTitle("Documents")
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
        }
    }

    // MARK: - What still has to be found

    private var outstanding: [DocumentItem] {
        children
            .flatMap(\.liveTasks)
            .filter(\.isOpen)
            .flatMap(\.liveDocuments)
            .filter { !$0.isOnHand }
    }

    /// Deduplicated by title **within one child**, because the same certified
    /// copy appears on four different tasks and a list that says "birth
    /// certificate" four times reads as four errands.
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

    private var uniqueOutstanding: [DocumentItem] {
        var seen = Set<String>()
        return outstanding.filter { seen.insert(identity($0)).inserted }
    }

    @ViewBuilder
    private var gatherSection: some View {
        let items = uniqueOutstanding
        Section {
            if items.isEmpty {
                Label("Everything your open tasks ask for is gathered.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(items) { item in
                    Button {
                        markGathered(item)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "square")
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let task = item.task {
                                    // The child's name leads once there is more
                                    // than one, because with twins the two rows
                                    // are otherwise the same words twice and the
                                    // parent cannot tell which one they just
                                    // found.
                                    Text(children.count > 1
                                         ? "\(task.child?.displayName ?? "Your baby") \u{00B7} \(task.title)"
                                         : task.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Still to find")
        } footer: {
            Text(children.count > 1
                 ? "Every open task's list in one place, with the duplicates collapsed. Ticking one here ticks it wherever else it appears for that child, and never for the other."
                 : "Every open task's list in one place, with the duplicates collapsed. Ticking one here ticks it wherever else it appears.")
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
    private func markGathered(_ item: DocumentItem) {
        let key = identity(item)
        for match in outstanding where identity(match) == key {
            match.isOnHand = true
            match.markedOnHandAt = Date()
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
                            VStack(alignment: .leading, spacing: 2) {
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
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in delete(offsets, from: documents) }

                addButton(for: child, existingCount: documents.count)
            }
        } header: {
            Text(children.count > 1 ? "\(child.displayName)'s copies" : "Your copies")
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
                addingFor = child
            } label: {
                Label("Add a document", systemImage: "photo.badge.plus")
            }
        } else {
            Button {
                navigator.requestUpgrade()
            } label: {
                HStack {
                    Label("Add a document", systemImage: "photo.badge.plus")
                    Spacer(minLength: 8)
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
            return "Photographs of the documents you already have, so you are not driving home for the certificate. They stay on this phone: they are not backed up, not uploaded, and Baby Docs has no server to put them on."
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
        VaultStore.shared.removePages(named: document.pageFileNames)
        document.pageFileNames = []
        document.tombstone(in: context)
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
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        .disabled(images.isEmpty)
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
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        images = loaded
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
        do {
            document.pageFileNames = try images.map { try VaultStore.shared.addPage($0) }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        context.insert(document)
        document.recordLocalChange(in: context)
        dismiss()
    }
}

// MARK: - Viewing

struct VaultDocumentViewer: View {
    @Environment(\.dismiss) private var dismiss
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
                        ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                            ZoomableImage(image: image)
                        }
                    }
                    .tabViewStyle(.page)
                    .background(Color.black)
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
