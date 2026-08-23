import Foundation
import SwiftData
import Testing

@testable import BabyDocs

/// The rules behind what Plus is, and behind the one gesture the plan screen
/// exists for.
///
/// Every assertion here is about a decision that is invisible in a diff: where a
/// ticked row goes, which notifications a free family still gets, and whether a
/// blocked task can be told apart from a task nobody has got round to.
@MainActor
struct PlusTierTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func task(
        title: String,
        key: String = "",
        dueInDays: Int?,
        kind: DeadlineKind,
        child: Child? = nil
    ) -> RequirementTask {
        let task = RequirementTask(title: title)
        task.catalogKey = key
        if let dueInDays {
            task.dueAt = Calendar.current.date(byAdding: .day, value: dueInDays, to: now)
        }
        task.deadlineKind = kind
        task.deadlineBasis = "Because the plan says so."
        task.child = child
        return task
    }

    // MARK: - A ticked task stays where it was

    @Test("Ticking a task leaves it in its own section rather than moving it away")
    func completedTasksStayInPlace() {
        let one = task(title: "Order the certificate", dueInDays: 3, kind: .recommended)
        one.completedAt = now

        let buckets = TaskPlanner.buckets(for: [one], now: now, completed: .inPlace)
        #expect(buckets.map(\.bucket) == [.thisWeek])
        #expect(buckets.first?.tasks.first?.id == one.id)
    }

    @Test("A task ticked in time never reappears under Past due")
    func completedInTimeIsNotLaterOverdue() {
        // Bucketed against today, a task finished comfortably inside its window
        // moves into "Past due" a fortnight later and tells a parent they missed
        // something they did not.
        let one = task(title: "Add the baby to the plan", dueInDays: 2, kind: .hard)
        one.completedAt = now
        let muchLater = Calendar.current.date(byAdding: .day, value: 40, to: now)!

        let buckets = TaskPlanner.buckets(for: [one], now: muchLater, completed: .inPlace)
        #expect(buckets.map(\.bucket) == [.thisWeek])
    }

    @Test("A task ticked after its date honestly says so")
    func completedLateStaysOverdue() {
        let one = task(title: "Add the baby to the plan", dueInDays: -5, kind: .hard)
        one.completedAt = now

        let buckets = TaskPlanner.buckets(for: [one], now: now, completed: .inPlace)
        #expect(buckets.map(\.bucket) == [.overdue])
    }

    @Test("Ticking a task does not move it up or down its section")
    func completedTasksKeepTheirPlace() {
        // Sinking them to the bottom is the same bug in a smaller box: on a
        // long section the row a parent just dealt with still leaves the part
        // of the screen they are looking at.
        let done = task(title: "A finished thing", dueInDays: 1, kind: .recommended)
        done.completedAt = now
        let open = task(title: "An open thing", dueInDays: 5, kind: .recommended)

        let sorted = TaskPlanner.sorted([done, open], now: now)
        #expect(sorted.map(\.title) == ["A finished thing", "An open thing"])
    }

    @Test("Dismissed is not completed and does leave the plan")
    func dismissedTasksLeave() {
        let one = task(title: "Does not apply", dueInDays: 3, kind: .recommended)
        one.dismissedAt = now

        let buckets = TaskPlanner.buckets(for: [one], now: now, completed: .inPlace)
        #expect(buckets.map(\.bucket) == [.done])
    }

    @Test("The exporter still prints a flat done list")
    func exporterKeepsItsOwnDoneBucket() {
        let one = task(title: "Order the certificate", dueInDays: 3, kind: .recommended)
        one.completedAt = now
        let buckets = TaskPlanner.buckets(for: [one], now: now)
        #expect(buckets.map(\.bucket) == [.done])
    }

    // MARK: - The timeline

    @Test("A task waiting on another one is shown as blocked, not as late")
    func blockedTasksAreCalledBlocked() {
        let child = Child(name: "Rosa", birthDate: now)
        let certificate = task(title: "Order copies", key: "birth_certificate", dueInDays: nil, kind: .none, child: child)
        let passport = task(title: "Apply for a passport", key: "passport", dueInDays: nil, kind: .none, child: child)

        let groups = PlanTimeline.groups(for: [certificate, passport], now: now)
        let blocked = groups.first { $0.phase == .blocked }
        #expect(blocked?.steps.map(\.title) == ["Apply for a passport"])
        #expect(blocked?.steps.first?.isBlocked == true)
        #expect(blocked?.steps.first?.reason.contains("certified copy") == true)
    }

    @Test("Finishing the thing it waits on opens the blocked task")
    func blockersClear() {
        let child = Child(name: "Rosa", birthDate: now)
        let certificate = task(title: "Order copies", key: "birth_certificate", dueInDays: nil, kind: .none, child: child)
        certificate.completedAt = now
        let passport = task(title: "Apply for a passport", key: "passport", dueInDays: nil, kind: .none, child: child)

        let groups = PlanTimeline.groups(for: [certificate, passport], now: now)
        #expect(groups.contains { $0.phase == .blocked } == false)
        let openNow = groups.first { $0.phase == .now }
        #expect(openNow?.steps.contains { $0.title == "Apply for a passport" } == true)
    }

    @Test("A hard window outranks every sequencing opinion in the catalog")
    func hardDeadlinesAlwaysComeFirst() {
        let child = Child(name: "Rosa", birthDate: now)
        // `guardian_nomination` says to leave this a month. A hard deadline on
        // the same row must still be treated as this week's work: the app's
        // view of what is convenient never reorders a date somebody else set.
        let one = task(title: "Name a guardian", key: "guardian_nomination", dueInDays: 4, kind: .hard, child: child)

        let groups = PlanTimeline.groups(for: [one], now: now)
        #expect(groups.map(\.phase) == [.now])
    }

    @Test("A dismissed task is off the timeline entirely")
    func dismissedIsOffTheTimeline() {
        let one = task(title: "Does not apply", dueInDays: 3, kind: .recommended)
        one.dismissedAt = now
        #expect(PlanTimeline.groups(for: [one], now: now).isEmpty)
    }

    // MARK: - What is free

    @Test("A free family still gets both warnings for a window that closes")
    func hardDeadlinesAreNeverGated() {
        let hard = task(title: "Add the baby to the plan", dueInDays: 30, kind: .hard)
        let plans = DeadlineReminderScheduler.plans(for: [hard], now: now, options: .hardDeadlinesOnly)
        #expect(plans.count == DeadlineReminderScheduler.leadDays.count)
        #expect(plans.allSatisfy { $0.isHardDeadline })
    }

    @Test("Suggested dates say nothing until they are switched on")
    func suggestedRemindersAreOptIn() {
        let suggested = task(title: "Check the record", dueInDays: 30, kind: .recommended)
        #expect(DeadlineReminderScheduler.plans(for: [suggested], now: now).isEmpty)

        let withPlus = DeadlineReminderScheduler.plans(
            for: [suggested],
            now: now,
            options: DeadlineReminderScheduler.Options(suggestedDates: true)
        )
        #expect(withPlus.count == DeadlineReminderScheduler.suggestedLeadDays.count)
        // Never dressed up as a legal window in the notification itself.
        #expect(withPlus.allSatisfy { !$0.isHardDeadline })
        #expect(withPlus.allSatisfy { $0.body.contains("not a legal deadline") })
    }

    @Test("A reminder the parent set only fires with Plus")
    func customRemindersAreGated() {
        let one = task(title: "Ring the benefits line", dueInDays: nil, kind: .none)
        one.customReminderAt = Calendar.current.date(byAdding: .day, value: 2, to: now)

        #expect(DeadlineReminderScheduler.plans(for: [one], now: now).isEmpty)
        let withPlus = DeadlineReminderScheduler.plans(
            for: [one],
            now: now,
            options: DeadlineReminderScheduler.Options(customReminders: true)
        )
        #expect(withPlus.count == 1)
        #expect(withPlus.first?.taskID == one.id)
    }

    @Test("A custom reminder cannot be set for a nine o'clock that has passed")
    func customReminderMinimumDateMovesToTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23))!
        let afterNine = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        #expect(
            DeadlineReminderScheduler.minimumCustomReminderDate(
                now: afterNine,
                calendar: calendar
            ) == tomorrow
        )
    }

    @Test("The weekly digest stays silent on a week with nothing in it")
    func digestSkipsEmptyWeeks() {
        let far = task(title: "Something in three months", dueInDays: 90, kind: .recommended)
        #expect(DeadlineReminderScheduler.digests(for: [far], now: now).isEmpty)
    }

    @Test("The weekly digest says whether any of the week is a real window")
    func digestNamesWhatIsReal() {
        let hard = task(title: "Add the baby to the plan", dueInDays: 30, kind: .hard)
        let soft = task(title: "Check the record", dueInDays: 30, kind: .recommended)
        #expect(DeadlineReminderScheduler.digestBody(for: [hard]).contains("real enrollment window"))
        #expect(DeadlineReminderScheduler.digestBody(for: [soft]).contains("not a legal deadline"))
        #expect(
            DeadlineReminderScheduler.digestBody(for: [hard, soft])
                .contains("1 of them is a real window closing")
        )
    }

    @Test("Suggestions and digests can never crowd out a hard deadline")
    func hardDeadlinesClaimTheBudgetFirst() {
        // The platform drops everything past its own pending limit, and a
        // fortnight of suggestions sorted by date would push the 60-day
        // Marketplace warning off the end of the queue.
        let hard = (1...4).map { task(title: "Window \($0)", dueInDays: 300 + $0, kind: .hard) }
        let noise = (1...60).map { task(title: "Suggestion \($0)", dueInDays: $0 + 5, kind: .recommended) }

        let plans = DeadlineReminderScheduler.plans(
            for: hard + noise,
            now: now,
            options: DeadlineReminderScheduler.Options(suggestedDates: true, weeklyDigest: true)
        )
        #expect(plans.count <= DeadlineReminderScheduler.maxScheduled)
        for task in hard {
            #expect(plans.filter { $0.taskID == task.id }.count == DeadlineReminderScheduler.leadDays.count)
        }
    }

    // MARK: - The calendar file

    @Test("The calendar carries the dates and nothing a parent typed")
    func calendarExportsDatesOnly() {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)

        let hard = task(title: "Add the baby, now", dueInDays: 20, kind: .hard, child: child)
        hard.parentNotes = "Ring Dana on 555-0100"
        context.insert(hard)
        let receipt = Receipt(kind: .confirmationNumber, value: "ABC-12345")
        receipt.task = hard
        context.insert(receipt)

        let text = CalendarExporter.ics(for: child, now: now)
        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("Add the baby"))
        #expect(!text.contains("555-0100"))
        #expect(!text.contains("ABC-12345"))
    }

    @Test("Calendar export omits task details that may contain household text")
    func calendarDoesNotExportTaskDetails() {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)
        let one = task(title: "Add the baby", dueInDays: 20, kind: .hard, child: child)
        one.detail = "Call Dana at 123-45-6789"
        context.insert(one)

        let text = CalendarExporter.ics(for: child, now: now)
        #expect(!text.contains("123-45-6789"))
        #expect(text.contains("SUMMARY:Deadline: Add the baby"))
    }

    @Test("A task with no date produces no calendar entry")
    func undatedTasksAreNotInvented() {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)
        let undated = task(title: "No date on this one", dueInDays: nil, kind: .none, child: child)
        context.insert(undated)

        let text = CalendarExporter.ics(for: child, now: now)
        #expect(!text.contains("BEGIN:VEVENT"))
    }

    @Test("A suggested date is labelled as one in the calendar too")
    func calendarNamesSuggestions() {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)
        let soft = task(title: "Check the record", dueInDays: 10, kind: .recommended, child: child)
        context.insert(soft)

        let text = CalendarExporter.ics(for: child, now: now)
        #expect(text.contains("Suggested: Check the record"))
        #expect(text.contains("Not a legal deadline"))
    }

    @Test("Calendar identifiers are stable, so a re-export updates rather than duplicates")
    func calendarIdentifiersAreStable() {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)
        let one = task(title: "Add the baby", dueInDays: 20, kind: .hard, child: child)
        context.insert(one)

        let first = CalendarExporter.ics(for: child, now: now)
        let second = CalendarExporter.ics(for: child, now: now)
        #expect(first.contains("UID:\(one.id.uuidString)@babydocs"))
        #expect(first == second)
    }
}

/// The preference store, which is worth its own suite for one reason: it used to
/// be written with `didSet` on an `@Observable` stored property, which is the
/// kind of thing that compiles, stops firing after a macro change, and loses the
/// setting silently on the next launch.
@MainActor
struct ReminderPreferenceTests {
    private func emptyDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "babydocs.tests.\(UUID().uuidString)")!
        return suite
    }

    @Test("Both extras default to on, and mean nothing until Plus is bought")
    func defaultsAreOn() {
        let prefs = ReminderPreferences(defaults: emptyDefaults())
        #expect(prefs.suggestedDateReminders)
        #expect(prefs.weeklyDigest)
        // The gate is the entitlement, not the switch.
        #expect(DeadlineReminderScheduler.Options.hardDeadlinesOnly.suggestedDates == false)
    }

    @Test("A switched-off preference survives the next launch")
    func preferencesPersist() {
        let defaults = emptyDefaults()
        let prefs = ReminderPreferences(defaults: defaults)
        prefs.setSuggestedDateReminders(false)
        prefs.setWeeklyDigest(false)

        let reopened = ReminderPreferences(defaults: defaults)
        #expect(reopened.suggestedDateReminders == false)
        #expect(reopened.weeklyDigest == false)
    }
}
