import Foundation

/// The plain-text one-pager.
///
/// Exists because a phone is the wrong device for a queue at a records office,
/// and because the other parent, the grandparent driving to the appointment and
/// the folder in the filing cabinet all need the same page. Plain text on
/// purpose: it survives being pasted into a message, printed, or read out.
///
/// It prints every section even when empty ("Documents needed: none listed"),
/// because a section that simply vanishes reads as a negative answer to whoever
/// is holding the page.
enum PlanExporter {
    static func summary(
        for child: Child,
        profile: FamilyProfile,
        now: Date = Date()
    ) -> String {
        var lines: [String] = []

        lines.append("NEWBORN PAPERWORK: \(child.displayName.uppercased())")
        lines.append("Born \(dateString(child.birthDate))\(birthPlaceSuffix(child))")
        if !profile.residenceStateCode.isEmpty {
            lines.append("Living in \(USState.displayName(for: profile.residenceStateCode))")
        }
        lines.append("Prepared \(dateString(now))")
        lines.append("")

        lines.append(contentsOf: identitySection(child))
        lines.append("")

        let tasks = child.liveTasks
        let overview = TaskPlanner.overview(for: tasks, now: now)
        lines.append("PROGRESS: \(overview.doneCount) of \(overview.totalCount) done")
        if let next = overview.nextHardDeadline, let title = overview.nextHardDeadlineTitle {
            lines.append("NEXT HARD DEADLINE: \(dateString(next)), \(title)")
        } else {
            lines.append("NEXT HARD DEADLINE: none outstanding")
        }
        lines.append("")

        for (bucket, items) in TaskPlanner.buckets(for: tasks, now: now) where bucket != .done {
            lines.append(bucket.title.uppercased())
            for task in items {
                lines.append(contentsOf: taskLines(task, now: now))
            }
            lines.append("")
        }

        let done = tasks.filter { $0.isDone }
        lines.append("DONE")
        if done.isEmpty {
            lines.append("  nothing yet")
        } else {
            for task in TaskPlanner.sorted(done, now: now) {
                let by = task.completedByName.isEmpty ? "" : " by \(task.completedByName)"
                lines.append("  \(task.title)\(by)")
                for receipt in task.liveReceipts where !receipt.value.isEmpty {
                    lines.append("    \(receipt.kind.label): \(receipt.value)")
                }
            }
        }
        lines.append("")

        lines.append(disclaimer)
        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    private static func identitySection(_ child: Child) -> [String] {
        var lines = ["IDENTITY DOCUMENTS"]
        lines.append("  Social Security: \(child.ssnStatus.label)")
        if let received = child.ssnReceivedAt {
            lines.append("    card received \(dateString(received))")
        }
        if let received = child.birthCertificateReceivedAt {
            lines.append("  Birth certificate: received \(dateString(received)), \(child.certifiedCopiesOnHand) certified copies on hand")
        } else {
            lines.append("  Birth certificate: not received")
        }
        // Never printed. The number itself has no business leaving the device in
        // a shareable text file, and the status above is the only thing anyone
        // reading this page actually needs.
        return lines
    }

    private static func taskLines(_ task: RequirementTask, now: Date) -> [String] {
        var lines: [String] = []
        let marker = task.deadlineKind == .hard ? "!" : " "
        let due = task.dueAt.map { " (\(dateString($0)), \(TaskPlanner.duePhrase(for: task, now: now)))" } ?? ""
        lines.append("  \(marker) \(task.title)\(due)")

        if !task.assigneeName.isEmpty {
            lines.append("      with \(task.assigneeName)")
        }
        let outstanding = task.liveDocuments.filter { !$0.isOnHand }
        if outstanding.isEmpty {
            lines.append("      documents: all gathered")
        } else {
            lines.append("      still need: \(outstanding.map(\.title).joined(separator: "; "))")
        }
        if !task.officialURLString.isEmpty {
            lines.append("      \(task.officialURLString)")
        }
        return lines
    }

    static let disclaimer = """
    Baby Docs tracks paperwork. It is not legal, tax, medical or insurance \
    advice, it does not file anything on your behalf, and deadlines set by your \
    own plan or your own state override anything printed here. Check the \
    official page linked against each task before you rely on a date.
    """

    // MARK: - Helpers

    private static func birthPlaceSuffix(_ child: Child) -> String {
        var parts: [String] = []
        if !child.birthCounty.isEmpty { parts.append(child.birthCounty) }
        if !child.birthStateCode.isEmpty { parts.append(USState.displayName(for: child.birthStateCode)) }
        return parts.isEmpty ? "" : " in \(parts.joined(separator: ", "))"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
