import SwiftUI

enum AppTheme {
    /// Each child gets a stable colour so a task, a document and a note all read
    /// as belonging to the same baby at a glance.
    static let childColors: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 0.86),
        Color(red: 0.88, green: 0.53, blue: 0.55),
        Color(red: 0.36, green: 0.68, blue: 0.55),
        Color(red: 0.66, green: 0.50, blue: 0.82),
        Color(red: 0.92, green: 0.68, blue: 0.32),
        Color(red: 0.32, green: 0.66, blue: 0.72)
    ]

    static func color(forChildIndex index: Int) -> Color {
        guard !childColors.isEmpty else { return .accentColor }
        return childColors[((index % childColors.count) + childColors.count) % childColors.count]
    }

    /// One colour per category, so a task is recognisable by its icon before its
    /// label is read. Ordered to match `RequirementCategory.colorIndex`.
    ///
    /// Icon tints only, never a text colour and never a fill behind text: at low
    /// opacity behind a saturated glyph they clear contrast in both appearances,
    /// which is the constraint that matters when the phone is being read
    /// one-handed at 3am.
    static let categoryColors: [Color] = [
        Color(red: 0.24, green: 0.51, blue: 0.85),  // identity
        Color(red: 0.85, green: 0.32, blue: 0.38),  // insurance
        Color(red: 0.45, green: 0.42, blue: 0.80),  // parentage
        Color(red: 0.24, green: 0.60, blue: 0.44),  // money
        Color(red: 0.25, green: 0.62, blue: 0.70),  // travel
        Color(red: 0.86, green: 0.55, blue: 0.20),  // work
        Color(red: 0.50, green: 0.50, blue: 0.55)   // household
    ]

    static func color(forCategoryIndex index: Int) -> Color {
        guard !categoryColors.isEmpty else { return .accentColor }
        return categoryColors[((index % categoryColors.count) + categoryColors.count) % categoryColors.count]
    }

    /// Deadline urgency. A hard deadline is never drawn in the same colour as a
    /// suggestion, in any state, because the difference between the two is the
    /// only thing this app is really selling.
    static func color(for kind: DeadlineKind, daysRemaining: Int?) -> Color {
        switch kind {
        case .hard:
            guard let daysRemaining else { return .red }
            if daysRemaining < 0 { return .red }
            return daysRemaining <= 7 ? .red : .orange
        case .recommended:
            guard let daysRemaining, daysRemaining < 0 else { return .orange }
            return .orange
        case .none:
            return .secondary
        }
    }

    static let cardCornerRadius: CGFloat = 14
}

extension RequirementCategory {
    var color: Color {
        AppTheme.color(forCategoryIndex: colorIndex)
    }
}

extension Child {
    var color: Color {
        AppTheme.color(forChildIndex: colorIndex)
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

extension RequirementTask {
    var accentColor: Color {
        AppTheme.color(for: deadlineKind, daysRemaining: daysRemaining())
    }
}
