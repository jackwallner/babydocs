import SwiftUI

/// The shared visual vocabulary. Anything that appears on more than one screen
/// lives here, so the plan, the child hub and the documents tab cannot drift into
/// three different ideas of what a deadline looks like.

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

/// "Sent three weeks ago and still not here." The one badge that is not about a
/// deadline, and it earns its place because it is the only thing in the app that
/// tells a parent something they could not have worked out themselves.
struct LatePill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.caption2)
            Text("Not arrived")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.red.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sent, and past the date it was expected back")
    }
}

// MARK: - Task row

/// A row in the plan: a tick box that completes the task, and everything else,
/// which pushes the detail screen.
///
/// The `NavigationLink` sits *beside* the `Button` rather than wrapping it, so
/// the two tap targets are separate areas rather than two controls competing
/// for the same one. The tick box also carries an explicit 44pt frame: its
/// glyph alone is well under the minimum target size, which is a miss on a
/// phone being held one-handed at 3am.
struct TaskRow: View {
    let task: RequirementTask
    var showChildName = false
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Button {
                onToggle?()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
                    // Without this the tap target is the glyph's own bounds,
                    // which is under the 44pt minimum.
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onToggle == nil)
            .accessibilityLabel(task.isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done")

            NavigationLink(value: task.id) {
                content
                    // Without both of these the link's hit area is the glyphs
                    // themselves, so a tap in the whitespace beside a short
                    // title lands on nothing and the row simply does not open.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 2)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            Text(task.title)
                .font(.body)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .strikethrough(task.isDone, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !task.isDone {
                // One wrapping row rather than two fixed ones. At an
                // accessibility text size these badges cannot share a line, and
                // the previous layout let them truncate to four characters each
                // instead of stacking.
                BadgeRow {
                    DeadlinePill(task: task)
                    if task.isLate() { LatePill() }
                    metadata
                }
            } else {
                metadata
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        HStack(spacing: 4) {
            Image(systemName: task.category.symbol)
                .font(.caption2)
            Text(secondaryLine)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(task.category.label). \(secondaryLine)")
    }

    /// Category, child and outstanding-document count in one grey line rather
    /// than three coloured fragments. Everything here is context, and context
    /// reads better as a sentence than as a row of chips.
    private var secondaryLine: String {
        var parts = [task.category.label]
        if showChildName, let name = task.child?.displayName { parts.append(name) }
        if !task.assigneeName.isEmpty { parts.append(task.assigneeName) }
        let outstanding = task.liveDocuments.filter { !$0.isOnHand }.count
        if outstanding > 0 && !task.isDone { parts.append("\(outstanding) to gather") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Document checklist row

/// One line of the gather list: a tick, what it is, which task wants it, and a
/// way through to that task.
///
/// Same shape as `TaskRow` on purpose, including the 44pt tick target and the
/// link sitting beside the button rather than around it. The two screens are
/// asking the same question about different nouns, so they should not look like
/// two different apps, and a tick box that is 22 points tall on one screen and
/// 44 on the other is a miss on the screen where somebody is standing at a
/// counter holding a baby.
struct DocumentChecklistRow: View {
    let item: DocumentItem
    var showChildName = false
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing) {
            Button(action: onToggle) {
                Image(systemName: item.isOnHand ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isOnHand ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isOnHand
                                ? "Mark \(item.title) not found yet"
                                : "Mark \(item.title) as in hand")

            link
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var link: some View {
        if let taskID = item.task?.id {
            NavigationLink(value: taskID) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } else {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .foregroundStyle(item.isOnHand ? .secondary : .primary)
                .strikethrough(item.isOnHand, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !secondaryLine.isEmpty {
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The child's name leads once there is more than one, because with twins
    /// the two rows are otherwise the same words twice and the parent cannot
    /// tell which one they just found.
    private var secondaryLine: String {
        guard let task = item.task else { return "" }
        var parts: [String] = []
        if showChildName { parts.append(task.child?.displayName ?? "Your baby") }
        parts.append(task.title)
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - The card at the top of the plan

/// One card, not two.
///
/// The plan used to open with a deadline slab and then a second, almost empty
/// slab underneath it holding "0 of 15 done" and a bar. Two cards of different
/// heights, saying two halves of one sentence, with a gap between them: the
/// screen read as assembled rather than designed, and the gap made the progress
/// bar look like it belonged to whatever came next. They are one card with a
/// rule through it now, which is what they always were.
///
/// The card is the task. Tapping it opens the deadline it names, so the parent
/// who reads "Thursday, 30 days left" does not then have to find the same title
/// again in the list below.
struct PlanHeaderCard: View {
    let overview: TaskPlanner.Overview

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing) {
            if let id = overview.nextHardDeadlineID {
                NavigationLink(value: id) {
                    deadlineBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                deadlineBlock
            }

            Divider()

            PlanProgressCard(overview: overview, isBare: true)
        }
        .planCard(padding: AppTheme.spacing + 2)
    }

    /// The card itself stays neutral. It used to be washed in red, which made
    /// the most important element on the home screen read as an error state and
    /// left no colour in reserve for the thing that actually is urgent. Red
    /// appears on exactly two lines: the eyebrow and the date.
    private var deadlineBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            HStack(spacing: AppTheme.tightSpacing) {
                Label {
                    Text(overview.nextHardDeadline == nil ? "Nothing closing" : "Next hard deadline")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                } icon: {
                    Image(systemName: overview.nextHardDeadline == nil
                          ? "checkmark.circle.fill"
                          : "exclamationmark.circle.fill")
                        .font(.caption)
                }
                .foregroundStyle(overview.nextHardDeadline == nil ? Color.green : Color.red)

                Spacer(minLength: 0)
                // No chevron of our own here. The row is a `NavigationLink`, and
                // the list draws the disclosure indicator itself: adding one put
                // two arrows on one card, six points apart, pointing at the same
                // destination.
            }

            if let date = overview.nextHardDeadline, let title = overview.nextHardDeadlineTitle {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // The same day string the row below uses. Two formats for one
                // date, six points apart, is what "it just looks bad" was made
                // of. See `TaskPlanner.deadlineLine`.
                Text(TaskPlanner.deadlineLine(for: date))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Every closing window is behind you. What is left has no date attached to it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Progress

/// Used bare inside `PlanHeaderCard`, and as its own card on the child detail,
/// which has no deadline block to sit under.
struct PlanProgressCard: View {
    let overview: TaskPlanner.Overview
    var isBare = false

    var body: some View {
        if isBare {
            content
        } else {
            content.planCard()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.tightSpacing) {
            BadgeRow {
                Text("\(overview.doneCount) of \(overview.totalCount) done")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Spacer(minLength: 0)
                if overview.overdueCount > 0 {
                    Text("\(overview.overdueCount) past due")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
            }
            // A real bar rather than the system hairline, which on a dark page
            // was close to invisible and made a screen showing genuine progress
            // look like a screen showing none.
            ProgressBar(value: overview.progress)
        }
    }
}

// MARK: - Section header

/// The heading above a group of rows, everywhere there is one.
///
/// The blurb used to be a `footer`, which put an explanation of a section
/// *underneath* the section it explained and immediately above the next one, so
/// every gap on the plan held a grey sentence belonging to the card above it and
/// sitting closer to the card below. Read top to bottom it looked like each
/// heading had lost its subtitle. It is a subtitle now.
struct PlanSectionHeader: View {
    let title: String
    var blurb: String = ""
    var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.tightSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if !blurb.isEmpty {
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.top, AppTheme.tightSpacing)
        .accessibilityElement(children: .combine)
    }
}

/// Six points tall with a visible track. `ProgressView`'s default is two points
/// of tinted line on a track that all but vanishes in dark mode.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

// MARK: - Source footnote

/// Where a rule came from, when it was last read, what it does not cover, and
/// when there is nothing honest to cite at all.
///
/// Shown on every generated task, not hidden behind an info button. A paperwork
/// app is asking to be trusted about dates that cost real money, and the only
/// honest way to earn that is to show your working, admit how old it is, and say
/// plainly when the answer is a state's rather than a page's.
struct SourceFootnote: View {
    let urlString: String
    let verifiedOn: Date?
    /// The catalog key, so the footnote can find the rule's declared source and
    /// its limitations. Empty for a task a parent typed themselves.
    var catalogKey: String = ""

    private var rule: RequirementRule? {
        catalogKey.isEmpty ? nil : RequirementCatalog.rule(key: catalogKey)
    }

    var body: some View {
        if let url = URL(string: urlString), !urlString.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Link(destination: url) {
                    Label("Where this comes from", systemImage: "text.book.closed")
                        .font(.caption)
                }
                if let entry = rule?.source {
                    Text(entry.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let verifiedOn {
                    Text(checkedLine(verifiedOn))
                        .font(.caption)
                        .foregroundStyle(rule?.source?.status == .awaitingReview ? .orange : .secondary)
                }
                if let limitations = rule?.source?.limitations, !limitations.isEmpty {
                    Text("What it does not tell you: \(limitations)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let reason = rule?.noSourceReason, !reason.isEmpty {
            // No link, and the reason there is none is the point. A task that
            // simply has no footnote reads as an oversight; this reads as a
            // limit the app knows about.
            Label {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkedLine(_ date: Date) -> String {
        let day = date.formatted(.dateTime.month().day().year())
        switch rule?.source?.status {
        case .awaitingReview: return "Link added \(day). Nobody has read this page end to end yet."
        case .federalFallback: return "Checked \(day). Federal page: your state or plan has the final word."
        default: return "Checked \(day)"
        }
    }
}

// MARK: - Gated controls

/// The one place a Plus-only row is marked as one, so the badge cannot drift
/// into three slightly different treatments across three screens.
struct PlusBadge: View {
    var body: some View {
        Text("Plus")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

/// The Plus one-pager, wherever it is offered.
struct SummaryShareControl: View {
    let summary: () -> String
    var title = "Share a one-page summary"
    var symbol = "square.and.arrow.up"
    var onUpgrade: (() -> Void)?

    @State private var store = StoreService.shared
    @State private var navigator = AppNavigator.shared

    var body: some View {
        if store.isPro {
            ShareLink(item: summary()) {
                Label(title, systemImage: symbol)
            }
        } else {
            Button {
                if let onUpgrade {
                    onUpgrade()
                } else {
                    navigator.requestUpgrade()
                }
            } label: {
                HStack {
                    Label(title, systemImage: symbol)
                    Spacer(minLength: 8)
                    PlusBadge()
                }
            }
            .accessibilityLabel("\(title). Included with Plus.")
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
        VStack(spacing: AppTheme.spacing) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
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
        .padding(.vertical, 28)
        .padding(.horizontal, AppTheme.looseSpacing)
    }
}
