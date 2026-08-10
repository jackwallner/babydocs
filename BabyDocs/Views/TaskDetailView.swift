import SwiftData
import SwiftUI

/// One task, end to end: why it applies, when it closes, what to bring, where to
/// go, who has it, and what came back.
///
/// The order of the sections is the order a parent needs them in, and it is not
/// negotiable. "Why this applies to you" is first because a personalised list
/// that cannot justify itself is a generic checklist. The official link sits
/// above the receipts because the link is the action and the receipt is the
/// aftermath.
struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: RequirementTask

    @State private var family = FamilyService.shared
    @State private var isAddingReceipt = false
    @State private var receiptKind: ReceiptKind = .confirmationNumber
    @State private var receiptValue = ""

    var body: some View {
        List {
            Section {
                Text(task.detail)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label(task.category.label, systemImage: task.category.symbol)
                    .foregroundStyle(task.category.color)
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
                SourceFootnote(urlString: task.sourceURLString, verifiedOn: task.sourceVerifiedOn)
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { task.recordLocalChange(in: context) }
        .alert("Record a confirmation", isPresented: $isAddingReceipt) {
            TextField("Number or reference", text: $receiptValue)
            Button("Save", action: saveReceipt)
            Button("Cancel", role: .cancel) { receiptValue = "" }
        } message: {
            Text("Whatever the office gave you back, so neither of you has to find the email again.")
        }
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
                     : "\(outstanding) still to find. Ticking one here shows it to the other parent too.")
            }
        }
    }

    @ViewBuilder
    private var ownerSection: some View {
        Section("Who has this") {
            if family.members.isEmpty {
                Text(task.assigneeName.isEmpty ? "Nobody assigned" : task.assigneeName)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Assigned to", selection: assigneeBinding) {
                    Text("Nobody").tag(UUID?.none)
                    ForEach(family.members) { member in
                        Text(member.resolvedName).tag(UUID?.some(member.id))
                    }
                }
            }
        }
    }

    private var assigneeBinding: Binding<UUID?> {
        Binding(
            get: { task.assigneeUserID },
            set: { newValue in
                task.assigneeUserID = newValue
                task.assigneeName = family.members.first { $0.id == newValue }?.displayName ?? ""
                task.recordLocalChange(in: context)
            }
        )
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
            Text("Confirmation and tracking numbers only. Do not put the Social Security number here: it is stored and synced as ordinary text.")
        }
    }

    // MARK: - Actions

    private func toggleDone() {
        if task.isDone {
            task.completedAt = nil
            task.completedByName = ""
        } else {
            task.completedAt = Date()
            task.completedByName = family.selfDisplayName
        }
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
        receipt.groupID = task.groupID
        receipt.recordedByName = family.selfDisplayName
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
