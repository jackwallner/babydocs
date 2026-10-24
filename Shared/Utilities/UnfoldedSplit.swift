import CoreGraphics
import SwiftUI

/// Pane frames for the unfolded iPhone Duo: the tabs on the leading side of the
/// fold, Documents on the trailing side, so what to do sits beside what to
/// bring and no row straddles the crease. `nil` keeps the single column (every
/// ordinary iPhone, the folded Duo, and the unfolded Duo held in portrait,
/// where each half would be too narrow).
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the compact Plan and Documents layouts.
    static let minimumPaneWidth: CGFloat = 360

    /// The tab bar that heads the leading pane while split, as on iPad, so
    /// both panes run to the display's bottom edge and no row ends against a
    /// floating bar.
    static let paneTabBarHeight: CGFloat = 44
    /// The gap above and below that bar.
    static let paneTabBarGap: CGFloat = 8
    /// The last stretch of the display over which both panes fade out while
    /// split, so the last visible line is never sliced mid-glyph.
    static let paneEdgeFade: CGFloat = 28

    /// How far each pane's own screen starts below the top safe area: the bar
    /// and its gaps while split, nothing folded. Both panes take it, so the
    /// Plan and Documents titles sit on one line either side of the fold.
    static func paneTopInset(_ split: UnfoldedSplit?) -> CGFloat {
        split == nil ? 0 : paneTabBarHeight + paneTabBarGap * 2
    }

    /// Zero folded, where the system's own bar sits on that edge.
    static func bottomFade(_ split: UnfoldedSplit?) -> CGFloat {
        split == nil ? 0 : paneEdgeFade
    }

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// What `RootView` measures to decide on a split.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat
    var fold: ClosedRange<CGFloat>?
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

extension View {
    /// iOS 27.1 moves a `NavigationStack`'s toolbar into a vertical bar on its
    /// trailing edge. In the leading pane that bar sits against the fold and
    /// narrows the Plan by about 84 pt, so it stays horizontal while split.
    @ViewBuilder
    func horizontalToolbarsInPanes(_ isSplit: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(isSplit ? .disabled : .automatic)
        } else {
            self
        }
    }
}
