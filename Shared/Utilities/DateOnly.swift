import Foundation

/// Calendar dates in this app are not moments in time.
///
/// SwiftUI's date picker gives us a `Date`, but a birthday, a filing window and
/// a source-review date must mean the same day when a family travels or sends a
/// plan to someone in another time zone. UTC noon is inside the same calendar
/// day for every US time zone, so it is a safe wire and storage representation.
enum DateOnly {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Reads the day the user picked in the device's current calendar and
    /// stores that day at UTC noon.
    static func canonical(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return dateFrom(components) ?? date
    }

    /// Repairs an older stored or linked date without interpreting it in the
    /// recipient's current time zone. Existing builds encoded a US local
    /// midnight as an ISO-8601 instant, whose UTC calendar day is still the
    /// intended US date.
    static func canonicalFromUTC(_ date: Date) -> Date {
        dateFrom(utc.dateComponents([.year, .month, .day], from: date)) ?? date
    }

    static func dayKey(_ date: Date) -> String {
        let components = utc.dateComponents([.year, .month, .day], from: canonicalFromUTC(date))
        return key(from: components)
    }

    /// Returns the day a clock on this device shows for an instant.
    ///
    /// Stored date-only values use UTC noon so they survive a trip between US
    /// time zones. A live instant such as "now" must still be read in the
    /// user's calendar, or a follow-up can become late just after UTC midnight.
    static func localDayKey(_ date: Date, calendar: Calendar = .current) -> String {
        key(from: calendar.dateComponents([.year, .month, .day], from: date))
    }

    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return dateFrom(DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        dayKey(lhs) == dayKey(rhs)
    }

    private static func dateFrom(_ components: DateComponents) -> Date? {
        var components = components
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return utc.date(from: components)
    }

    private static func key(from components: DateComponents) -> String {
        String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
