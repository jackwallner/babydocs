import SwiftUI

/// The shared visual vocabulary. Anything that appears on more than one screen
/// lives here, so the plan, the child hub and the export cannot drift into three
/// different ideas of what a deadline looks like.

// MARK: - Deadline pill

/// The single most important control in the app: it is what tells a parent, in
/// one glance, whether a date is a suggestion or a door closing.
///
/// A hard deadline is never drawn the same as a recommendation, in any state.
/// Colour alone would not be enough (it fails for anyone who cannot see the
/// difference), so the hard case also carries a filled exclamation glyph.
struct DeadlinePill: View {
    let task: RequirementTask
    var compact = false

    private var days: Int? { task.daysRemaining() }

    var body: some View {
        HStack(spacing: 4) {
            if task.deadlineKind == .hard {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
            }
            Text(TaskPlanner.duePhrase(for: task))
                .font(compact ? .caption2 : .caption)
                .fontWeight(task.deadlineKind == .hard ? .semibold : .regular)
        }
        .foregroundStyle(task.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(task.accentColor.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            task.deadlineKind == .hard
                ? "Hard deadline. \(TaskPlanner.duePhrase(for: task))"
                : TaskPlanner.duePhrase(for: task)
        )
    }
}

// MARK: - Task row

struct TaskRow: View {
    let task: RequirementTask
    var showChildName = false
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggle?()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(onToggle == nil)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .strikethrough(task.isDone, color: .secondary)

                HStack(spacing: 6) {
                    Label(task.category.label, systemImage: task.category.symbol)
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(task.category.color)
                    if showChildName, let name = task.child?.displayName {
                        Text(name).font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if !task.isDone {
                    HStack(spacing: 6) {
                        DeadlinePill(task: task)
                        if !task.assigneeName.isEmpty {
                            Text(task.assigneeName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if outstandingDocuments > 0 {
                            Text("\(outstandingDocuments) to gather")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var outstandingDocuments: Int {
        task.liveDocuments.filter { !$0.isOnHand }.count
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let value: String
    let caption: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(caption)")
    }
}

// MARK: - Next deadline card

/// The one thing worth putting in front of someone who has thirty seconds and
/// one hand free.
struct NextDeadlineCard: View {
    let overview: TaskPlanner.Overview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(overview.nextHardDeadline == nil ? "No hard deadlines left" : "Next hard deadline")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if let date = overview.nextHardDeadline, let title = overview.nextHardDeadlineTitle {
                Text(title)
                    .font(.headline)
                Text(date, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text("Everything with a closing window is done or does not apply to you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(overview.nextHardDeadline == nil ? Color.green.opacity(0.10) : Color.red.opacity(0.08))
        )
    }
}

// MARK: - Progress card

struct PlanProgressCard: View {
    let overview: TaskPlanner.Overview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(overview.doneCount) of \(overview.totalCount) done")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if overview.overdueCount > 0 {
                    Text("\(overview.overdueCount) past due")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            ProgressView(value: overview.progress)
                .tint(.accentColor)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }
}

// MARK: - Source footnote

/// Where a rule came from and when it was last read.
///
/// Shown on every generated task, not hidden behind an info button. A paperwork
/// app is asking to be trusted about dates that cost real money, and the only
/// honest way to earn that is to show your working and admit how old it is.
struct SourceFootnote: View {
    let urlString: String
    let verifiedOn: Date?

    var body: some View {
        if let url = URL(string: urlString), !urlString.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Link(destination: url) {
                    Label("Where this comes from", systemImage: "text.book.closed")
                        .font(.caption)
                }
                if let verifiedOn {
                    Text("Checked \(verifiedOn, format: .dateTime.month().day().year())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
