import SwiftData
import SwiftUI

/// One task, end to end: why it applies, when it closes, what to bring, where to
/// go, what has been sent, and what came back.
///
/// The order of the sections is the order a parent needs them in, and it is not
/// negotiable. "Why this applies to you" is first because a personalised list
/// that cannot justify itself is a generic checklist. The official link sits
/// above the receipts because the link is the action and the receipt is the
/// aftermath.
struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: RequirementTask

    @State private var isAddingReceipt = false
    @State private var receiptKind: ReceiptKind = .confirmationNumber
    @State private var receiptValue = ""

    var body: some View {
        List {
            Section {
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(task.detail)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label(task.category.label, systemImage: task.category.symbol)
                    .foregroundStyle(.secondary)
            }

            deadlineSection

            if let url = task.officialURL {
                Section("Where to do it") {
                    Link(destination: url) {
                        Label(
                            task.officialLinkLabel.isEmpty ? "Open the official page" : task.officialLinkLabel,
                            systemImage: "arrow.up.right.square"
                        )
                    }
                    Text("Baby Docs never submits anything for you. This opens the official site so you file it yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            documentsSection
            if task.isPostedAway { followUpSection }
            ownerSection
            receiptsSection

            Section("Your notes") {
                TextField(
                    "Anything you want to remember",
                    text: $task.parentNotes,
                    axis: .vertical
                )
                .lineLimit(2...6)
                .onSubmit { task.recordLocalChange(in: context) }
            }

            Section {
                Button(task.isDone ? "Mark not done" : "Mark done", action: toggleDone)
                Button(task.isDismissed ? "Put back on the list" : "Does not apply to us", action: toggleDismissed)
                    .foregroundStyle(task.isDismissed ? Color.accentColor : Color.secondary)
            } footer: {
                if !task.catalogKey.isEmpty {
                    Text("Dismissing keeps this off your plan even after the plan is rebuilt.")
                }
            }

            Section {
                SourceFootnote(
                    urlString: task.sourceURLString,
                    verifiedOn: task.sourceVerifiedOn,
                    catalogKey: task.catalogKey
                )
            }
        }
        .listStyle(.insetGrouped)
        .planPageBackground()
        // The full title is a sentence and truncates to "Order certified copies
        // of the birth cer..." in a nav bar. The heading above still carries the
        // whole thing, and so does VoiceOver.
        .navigationTitle(shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(task.title)
        .onDisappear { task.recordLocalChange(in: context) }
        .alert("Record a confirmation", isPresented: $isAddingReceipt) {
            TextField("Number or reference", text: $receiptValue)
            Button("Save", action: saveReceipt)
            Button("Cancel", role: .cancel) { receiptValue = "" }
        } message: {
            Text("Whatever the office gave you back, so you do not have to find the email again.")
        }
    }

    /// The catalog's own short label, falling back to the full title for a task
    /// a parent typed in themselves.
    private var shortTitle: String {
        RequirementCatalog.rule(key: task.catalogKey)?.shortTitle ?? task.title
    }

    // MARK: - Sections

    @ViewBuilder
    private var deadlineSection: some View {
        Section {
            HStack {
                DeadlinePill(task: task)
                Spacer()
                if let due = task.dueAt {
                    Text(due, format: .dateTime.weekday().month().day().year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !task.deadlineBasis.isEmpty {
                Text(task.deadlineBasis)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(headerText)
        }
    }

    private var headerText: String {
        switch task.deadlineKind {
        case .hard: return "Hard deadline"
        case .recommended: return "Suggested by"
        case .none: return "Timing"
        }
    }

    @ViewBuilder
    private var documentsSection: some View {
        let documents = task.liveDocuments
        if !documents.isEmpty {
            Section {
                ForEach(documents) { item in
                    Button {
                        item.isOnHand.toggle()
                        item.markedOnHandAt = item.isOnHand ? Date() : nil
                        item.recordLocalChange(in: context)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.isOnHand ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.isOnHand ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !item.detail.isEmpty {
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Have these ready")
            } footer: {
                let outstanding = documents.filter { !$0.isOnHand }.count
                Text(outstanding == 0
                     ? "Everything on this list is gathered."
                     : "\(outstanding) still to find. They are collected with everything else on the Documents tab.")
            }
        }
    }

    /// The half of the job a checklist drops.
    ///
    /// Ticking "ordered the certificates" is not finishing the errand, it is
    /// starting a wait, and the wait is where things actually go wrong: the
    /// request was never received, the cheque was returned, the address was
    /// wrong. Nothing else in a parent's life is going to raise its hand about
    /// that, so the app asks for two dates and then does.
    ///
    /// The expected date is typed in, never guessed. Processing times move
    /// constantly and differ by county, so the only figure worth acting on is
    /// the one this family was actually told.
    @ViewBuilder
    private var followUpSection: some View {
        Section {
            Toggle("Sent it", isOn: submittedBinding)

            if task.submittedAt != nil {
                DatePicker("Sent on", selection: submittedDateBinding, displayedComponents: .date)
                DatePicker(
                    "They said by",
                    selection: expectedBinding,
                    displayedComponents: .date
                )
                if task.isLate() {
                    Label {
                        Text("This is past the date you were given. That is usually worth a phone call rather than more waiting.")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                    }
                    .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Sent and waiting")
        } footer: {
            Text(task.submittedAt == nil
                 ? "Once this is posted or filed, record when it went and what the office told you to expect. The plan will say something when that date passes."
                 : "No turnaround is guessed here. Whatever the office told you is the only figure worth acting on, because it differs by county and changes constantly.")
        }
    }

    @ViewBuilder
    private var ownerSection: some View {
        Section {
            TextField("Nobody assigned", text: $task.assigneeName)
                .onSubmit { task.recordLocalChange(in: context) }
        } header: {
            Text("Who has this")
        } footer: {
            Text("A name, for your own benefit. Both of you keep your own copy of the plan, so this does not appear on their phone.")
        }
    }

    @ViewBuilder
    private var receiptsSection: some View {
        Section {
            ForEach(task.liveReceipts) { receipt in
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.value.isEmpty ? receipt.kind.label : receipt.value)
                        .font(.body.monospaced())
                    Text("\(receipt.kind.label) \u{00B7} \(receipt.recordedAt, format: .dateTime.month().day())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: deleteReceipts)

            Menu {
                ForEach(ReceiptKind.allCases, id: \.self) { kind in
                    Button(kind.label) {
                        receiptKind = kind
                        isAddingReceipt = true
                    }
                }
            } label: {
                Label("Record what came back", systemImage: "plus.circle")
            }
        } header: {
            Text("Confirmations")
        } footer: {
            Text("Confirmation and tracking numbers only. Do not put the Social Security number here: it is stored as ordinary text.")
        }
    }

    // MARK: - Bindings

    private var submittedBinding: Binding<Bool> {
        Binding(
            get: { task.submittedAt != nil },
            set: { isSent in
                if isSent {
                    task.submittedAt = Date()
                    // Two weeks is a placeholder for the picker to open on, not
                    // a claim about any office. The footer says so, and the
                    // parent replaces it with what they were told.
                    task.expectedByAt = Calendar.current.date(byAdding: .day, value: 14, to: Date())
                } else {
                    task.submittedAt = nil
                    task.expectedByAt = nil
                }
                task.recordLocalChange(in: context)
            }
        )
    }

    private var submittedDateBinding: Binding<Date> {
        Binding(
            get: { task.submittedAt ?? Date() },
            set: { task.submittedAt = $0; task.recordLocalChange(in: context) }
        )
    }

    private var expectedBinding: Binding<Date> {
        Binding(
            get: { task.expectedByAt ?? Date() },
            set: { task.expectedByAt = $0; task.recordLocalChange(in: context) }
        )
    }

    // MARK: - Actions

    private func toggleDone() {
        task.completedAt = task.isDone ? nil : Date()
        task.recordLocalChange(in: context)
    }

    private func toggleDismissed() {
        task.dismissedAt = task.isDismissed ? nil : Date()
        task.recordLocalChange(in: context)
    }

    private func saveReceipt() {
        let trimmed = receiptValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let receipt = Receipt(kind: receiptKind, value: trimmed)
        receipt.task = task
        context.insert(receipt)
        receipt.recordLocalChange(in: context)
        receiptValue = ""
    }

    private func deleteReceipts(at offsets: IndexSet) {
        let receipts = task.liveReceipts
        for index in offsets where receipts.indices.contains(index) {
            receipts[index].tombstone(in: context)
        }
    }
}
