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
///
/// **Nothing from the document vault ever appears here, and that is enforced
/// rather than remembered.** This type is handed a `Child` and a `FamilyProfile`
/// and reads neither `vaultDocuments` nor any filename, so there is no path from
/// a share sheet to an image of a Social Security card. `SourceIntegrityTests`
/// asserts it on every build.
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

    // MARK: - Employer packet

    /// The page you hand to HR, or paste into the benefits portal's message box.
    ///
    /// Separate from the summary because it answers a different question. The
    /// summary is "what is left to do"; this is "here is my qualifying life
    /// event, here is the date, here is what I am enclosing", which is the exact
    /// shape a benefits administrator needs and the exact thing a parent has
    /// never written before. The 30-day window is the hardest deadline in the
    /// app, and the commonest way it is missed is not forgetting: it is sending
    /// something that gets bounced back for missing a date.
    static func employerPacket(
        for child: Child,
        profile: FamilyProfile,
        now: Date = Date()
    ) -> String {
        var lines: [String] = []
        let insurance = child.liveTasks.first { $0.catalogKey == "insurance_employer" }

        lines.append("QUALIFYING LIFE EVENT: BIRTH OF A CHILD")
        lines.append("")
        lines.append("Event: birth")
        lines.append("Date of event: \(dateString(child.birthDate))")
        if !child.name.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Dependent: \(child.name)")
        }
        lines.append("Dependent's date of birth: \(dateString(child.birthDate))")
        lines.append("Relationship: child")
        if let due = insurance?.dueAt {
            lines.append("Enrollment window closes: \(dateString(due))")
        }
        lines.append("")

        lines.append("REQUESTING")
        lines.append("  Add this dependent to my medical coverage, effective the date of birth.")
        if profile.hasDependentCareFSA {
            lines.append("  Change my dependent care FSA election for this qualifying event.")
        }
        lines.append("")

        lines.append("ENCLOSED")
        let documents = insurance?.liveDocuments ?? []
        if documents.isEmpty {
            lines.append("  (see the plan's own document list)")
        } else {
            for document in documents {
                lines.append("  \(document.isOnHand ? "[x]" : "[ ]") \(document.title)")
            }
        }
        lines.append("")

        lines.append("SOCIAL SECURITY NUMBER")
        switch child.ssnStatus {
        case .cardReceived:
            lines.append("  Issued. I will provide it directly on your form, not in this message.")
        case .requestedAtHospital, .appliedDirectly:
            lines.append("  Applied for, not yet issued. Most plans accept an enrollment marked")
            lines.append("  \"SSN applied for\" and take the number when it arrives. Please confirm")
            lines.append("  the enrollment is not held up waiting for it.")
        case .unknown:
            lines.append("  Status not yet confirmed.")
        }
        // The number itself is never printed here, on the same rule as the
        // summary, and for a sharper reason: this page is written to be emailed
        // to a third party and forwarded inside a company.
        lines.append("")

        if let basis = insurance?.deadlineBasis, !basis.isEmpty {
            lines.append("WHY THIS WINDOW")
            lines.append("  \(basis)")
            lines.append("")
        }
        if let url = insurance?.officialURLString, !url.isEmpty {
            lines.append("  \(url)")
            lines.append("")
        }

        lines.append("Prepared \(dateString(now)) with Baby Docs. Your plan's own rules and")
        lines.append("deadlines override anything on this page.")
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
        if let sent = task.submittedAt {
            var line = "      sent \(dateString(sent))"
            if let expected = task.expectedByAt {
                line += task.isLate(from: now)
                    ? ", was due back \(dateString(expected)) — chase this"
                    : ", expected back \(dateString(expected))"
            }
            lines.append(line)
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
