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

    // MARK: - Urgency owns colour

    /// **One colour system, and it means one thing: how close a door is to
    /// closing.** Nothing else in this app is allowed to be coloured.
    ///
    /// The screen this replaced had three competing systems in a single row: a
    /// blue category label, an orange due pill and a red banner above them, none
    /// of which were about each other. The eye had no way to know which colour
    /// was the important one, so all three stopped being information and became
    /// decoration. Categories are now a grey glyph, because their job is
    /// recognition, not alarm, and grey is perfectly good at recognition.
    static func color(for kind: DeadlineKind, daysRemaining: Int?) -> Color {
        switch kind {
        case .hard:
            guard let daysRemaining else { return .red }
            if daysRemaining < 0 { return .red }
            return daysRemaining <= 7 ? .red : .orange
        case .recommended:
            return .orange
        case .none:
            return .secondary
        }
    }

    // MARK: - Surfaces

    /// The page behind everything.
    ///
    /// Explicitly painted rather than left to the system, and that is what makes
    /// the floating tab bar work. A flat black page gives the glass nothing to
    /// blur, so the bar reads as a grey slab sitting on a void with black gaps
    /// around it. A real background means content passes under the bar and
    /// through it, which is the whole point of the shape.
    static var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }

    /// Cards, rows, anything raised off the page.
    static var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    /// A card that needs to sit on top of another card.
    static var raisedSurface: Color { Color(uiColor: .tertiarySystemGroupedBackground) }

    static let cardCornerRadius: CGFloat = 14

    /// **The one horizontal margin in the app.**
    ///
    /// Every card, every section and every row starts here. The old Plan screen
    /// set a custom inset on its two header cards and left the task list on the
    /// system default, so one screen had two left edges about fourteen points
    /// apart. Nothing about that is legible as a decision, and it is most of why
    /// the screen read as unfinished: the eye reads a broken vertical line long
    /// before it reads a heading.
    ///
    /// The number is 20 rather than a taste of our own, because that is what
    /// `.insetGrouped` uses for its own cards on iPhone. Settings and the
    /// sources list are system lists and always will be, so picking any other
    /// value guarantees that the hand-built screens and the system ones sit on
    /// two different left edges, one tab apart, which is the same bug the
    /// paragraph above is about with a longer commute.
    static let margin: CGFloat = 20

    /// Vertical rhythm. Three values, used everywhere, so spacing is chosen from
    /// a set rather than typed fresh each time.
    static let tightSpacing: CGFloat = 6
    static let spacing: CGFloat = 12
    static let looseSpacing: CGFloat = 20

    /// The cushion under the last row of a list, above the floating tab bar.
    ///
    /// This was 96, and 96 was a symptom. `planPageBackground` used to wrap
    /// every page in a `GeometryReader` and hand the scroll view an explicit
    /// height, which is exactly the shape that stops the system's own tab-bar
    /// safe area from reaching the list. With the inset gone the page had to
    /// buy it back by hand, first at 44 (too little, six screens clipped) and
    /// then at 96, which over-corrected into 96 points of dead page *and* a
    /// hard clipped edge where the shortened scroll view ended, one glass bar
    /// away from the bottom of the screen. That edge is the "big bar in the
    /// way" in the screenshots: content stopped dead above the bar instead of
    /// passing under it.
    ///
    /// The scroll view is full height again, so the system contributes the
    /// bar's own footprint. This is only breathing room on top of it.
    static let floatingTabBarInset: CGFloat = 24
}

extension RequirementCategory {
    /// Deliberately not a hue. See `AppTheme.color(for:daysRemaining:)`: the
    /// category tells you what kind of errand this is, which is a recognition
    /// job that a glyph does better than a colour, and spending colour on it is
    /// what stopped colour meaning "this is closing".
    var tint: Color { .secondary }
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

// MARK: - Shared modifiers

extension View {
    /// A card that lines up with every other card on the screen.
    ///
    /// Used as a list row, it zeroes the row insets and paints the page colour
    /// behind itself, so the card's own edges are the only edges. That is what
    /// keeps a header card and the task section below it on the same two
    /// vertical lines.
    func planCard(padding: CGFloat = AppTheme.spacing) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    /// Applied to a card used as a `List` row. Pairs with `planCard`.
    func planCardRow() -> some View {
        self
            .listRowInsets(EdgeInsets(
                top: AppTheme.tightSpacing,
                leading: AppTheme.margin,
                bottom: AppTheme.tightSpacing,
                trailing: AppTheme.margin
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The page treatment every top-level screen wears.
    ///
    /// Hiding the scroll background and painting our own gives every page one
    /// continuous surface behind the system's floating tab bar. The list itself
    /// ends before the bar, so its rows cannot become unreadable behind glass.
    ///
    /// The scroll view keeps its full height on purpose. It used to be given an
    /// explicit one, 96 points short, inside a `GeometryReader`: that both cut
    /// the page off at a hard horizontal edge above the bar and stopped the
    /// system from insetting the list for the bar at all, which is why the inset
    /// had to be guessed twice and was wrong twice. Full height, plus the
    /// system's own safe area, plus a cushion, is the whole arrangement.
    ///
    /// The last row of every list still has to clear the bar: on a task detail
    /// it is the source footnote, the one element that carries the app's whole
    /// claim to be checkable. `LayoutUITests` asserts it stays reachable.
    ///
    /// Pass `underTabBar: false` on a sheet. A sheet is presented over the tab
    /// bar rather than behind it, so reserving the bar's height there is 96
    /// points of empty page under the last row and nothing else.
    func planPageBackground(underTabBar: Bool = true) -> some View {
        self
            .scrollContentBackground(.hidden)
            .contentMargins(
                .bottom,
                underTabBar ? AppTheme.floatingTabBarInset : AppTheme.looseSpacing,
                for: .scrollContent
            )
            .background(AppTheme.pageBackground.ignoresSafeArea())
    }
}

// MARK: - Wrapping badge row

/// Lays badges out in a row, and drops to a column when they will not fit.
///
/// This exists because of a screenshot. At an accessibility text size the plan's
/// task rows put a due pill, an assignee and a document count on one line, ran
/// out of width, and each one truncated to about four characters. `ViewThatFits`
/// is the whole fix: it measures the row and takes the column instead, so the
/// large-text layout is a different shape rather than the same shape unreadable.
struct BadgeRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.tightSpacing) { content }
            VStack(alignment: .leading, spacing: AppTheme.tightSpacing) { content }
        }
    }
}
