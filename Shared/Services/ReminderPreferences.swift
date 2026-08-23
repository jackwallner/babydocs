import Foundation

/// What the family has asked to be told about, beyond the two dates that close.
///
/// Stored in `UserDefaults` rather than SwiftData on purpose: these are settings
/// for this phone, not household facts, and they must survive being read from
/// the scheduler at launch without touching the store.
///
/// **Both default to on and both mean nothing without Plus.** The scheduler
/// asks `StoreService` for that, once, at the point of scheduling, so a lapse
/// quietly stops the extra reminders instead of leaving a preference switched on
/// that does not do anything. The two hard deadlines are never affected by
/// anything in here: they are scheduled for everybody, forever, free.
///
/// Written through explicit setters rather than `didSet`, because a property
/// observer on an `@Observable` stored property is exactly the kind of thing
/// that compiles, stops firing after a macro change, and loses a preference
/// silently on the next launch.
@MainActor
@Observable
final class ReminderPreferences {
    static let shared = ReminderPreferences()

    private enum Key {
        static let suggested = "babydocs.reminders.suggested"
        static let digest = "babydocs.reminders.digest"
    }

    /// Nudges for the dates the app suggests rather than the ones the law sets.
    /// Thirteen of the twenty-three rules have one, and none of them got a
    /// notification before this existed.
    private(set) var suggestedDateReminders: Bool

    /// One message on a Sunday morning naming what the week holds, and nothing
    /// at all on a week that holds nothing.
    private(set) var weeklyDigest: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.suggestedDateReminders = defaults.object(forKey: Key.suggested) as? Bool ?? true
        self.weeklyDigest = defaults.object(forKey: Key.digest) as? Bool ?? true
    }

    func setSuggestedDateReminders(_ value: Bool) {
        suggestedDateReminders = value
        defaults.set(value, forKey: Key.suggested)
    }

    func setWeeklyDigest(_ value: Bool) {
        weeklyDigest = value
        defaults.set(value, forKey: Key.digest)
    }
}
