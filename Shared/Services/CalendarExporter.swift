import Foundation

/// The plan as calendar entries, so the dates live where the family already
/// looks.
///
/// The app's own reminders are good at one thing: they fire at 9am three days
/// before a window closes, on this phone, for the person holding it. A calendar
/// is good at a different thing: the other parent sees it, it survives a new
/// phone, and it sits beside the pediatrician appointment that the paperwork is
/// actually competing with. Neither replaces the other, which is why this
/// exports rather than syncs.
///
/// **Only dates go in.** Every event carries the task, why the date exists and
/// the official link, and nothing else: no notes the parent typed, no receipt
/// values, no document filenames, and nothing whatsoever from the vault, which
/// this type cannot reach because it never touches `vaultDocuments`. An `.ics`
/// file is a thing people mail to each other, and a calendar entry that leaks a
/// confirmation number into somebody's work account is a leak the family never
/// agreed to.
enum CalendarExporter {
    /// One all-day event per dated task. Tasks with no date are deliberately
    /// absent: an event on a day nobody chose is worse than no event.
    static func ics(for child: Child, now: Date = Date()) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Baby Docs//Newborn paperwork//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:Baby Docs deadlines"
        ]

        for task in TaskPlanner.sorted(child.liveTasks.filter(isExportable), now: now) {
            guard let dueAt = task.dueAt else { continue }
            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                // Derived from the task id, which is itself derived from
                // (child, catalog key). Re-exporting after a change updates the
                // family's existing entry instead of laying a second copy of
                // every deadline beside the first.
                "UID:\(task.id.uuidString)@babydocs",
                "DTSTAMP:\(timestamp(now))",
                "DTSTART;VALUE=DATE:\(day(dueAt))",
                "DTEND;VALUE=DATE:\(day(nextDay(after: dueAt)))",
                "SUMMARY:\(escape(summary(for: task)))",
                "DESCRIPTION:\(escape(description(for: task)))"
            ])
            if let url = task.officialURL {
                lines.append("URL:\(url.absoluteString)")
            }
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the file somewhere a share sheet can pick it up.
    ///
    /// The temporary directory, not the app container: this is a copy being
    /// handed out, and the container is where the things that never leave live.
    static func write(_ ics: String, named name: String) throws -> URL {
        let safe = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe.isEmpty ? "baby-docs" : safe)
            .appendingPathExtension("ics")
        try ics.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Done and dismissed tasks stay out. A calendar full of things somebody
    /// already did is the reason people stop importing calendars.
    private static func isExportable(_ task: RequirementTask) -> Bool {
        task.deletedAt == nil && task.isOpen && task.dueAt != nil
    }

    private static func summary(for task: RequirementTask) -> String {
        let prefix = task.deadlineKind == .hard ? "Deadline" : "Suggested"
        let title = RequirementCatalog.rule(key: task.catalogKey)?.shortTitle
            ?? PlanSeed.safeExternalText(task.title)
        return "\(prefix): \(title)"
    }

    private static func description(for task: RequirementTask) -> String {
        var parts: [String] = []
        if task.deadlineKind == .hard {
            parts.append("A window that closes.")
        } else {
            parts.append("Suggested by Baby Docs. Not a legal deadline.")
        }
        if !task.deadlineBasis.isEmpty { parts.append(task.deadlineBasis) }
        parts.append(PlanExporter.disclaimer)
        return parts.joined(separator: "\n\n")
    }

    private static func nextDay(after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private static func day(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// RFC 5545 text escaping. Unescaped, a task title with a comma in it ends
    /// the property early and the entry arrives truncated or not at all.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// RFC 5545 line folding at 75 octets. Long descriptions are the norm here,
    /// and some calendar clients simply drop an over-long line.
    private static func fold(_ line: String) -> String {
        let bytes = Array(line.utf8)
        guard bytes.count > 75 else { return line }

        var folded = ""
        var index = 0
        var limit = 75
        while index < bytes.count {
            var end = min(index + limit, bytes.count)
            // Never split a multi-byte character in half.
            while end > index && end < bytes.count && (bytes[end] & 0xC0) == 0x80 {
                end -= 1
            }
            let chunk = String(decoding: bytes[index..<end], as: UTF8.self)
            folded += index == 0 ? chunk : "\r\n \(chunk)"
            index = end
            limit = 74
        }
        return folded
    }
}
