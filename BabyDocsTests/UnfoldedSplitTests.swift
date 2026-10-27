import CoreGraphics
import Testing

@testable import BabyDocs

struct UnfoldedSplitTests {
    @Test func compactWidthNeverSplits() {
        // The folded Duo's outer display, and every ordinary iPhone.
        #expect(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil) == nil)
        #expect(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 455.5...495.5) == nil)
    }

    @Test func regularButTooNarrowStaysOneColumn() {
        // The unfolded Duo held in portrait: two halves would each be under 360 pt.
        #expect(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil) == nil)
    }

    @Test func panesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 455.5...495.5)
        #expect(split == UnfoldedSplit(primaryWidth: 455.5, secondaryX: 495.5, secondaryWidth: 455.5))
    }

    @Test func noFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        #expect(split == UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    @Test func aFoldLeavingANarrowPaneIsIgnored() {
        // A fold this far over would squeeze the leading pane below 360 pt.
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 300...340)
        #expect(split == UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    @Test func exactlyTwoMinimumPanesSplits() {
        let split = UnfoldedSplit.make(width: 720, isRegularWidth: true, fold: nil)
        #expect(split?.primaryWidth == UnfoldedSplit.minimumPaneWidth)
        #expect(split?.secondaryWidth == UnfoldedSplit.minimumPaneWidth)
    }

    @Test func foldedKeepsThePhoneEdges() {
        // Folded, the system's bottom bar is the phone's and nothing moves.
        #expect(UnfoldedSplit.chrome(nil, safeTop: 82) == PaneChrome(barTop: 0, contentInset: 0))
        #expect(UnfoldedSplit.bottomFade(nil) == 0)
    }

    @Test func barSitsInTheStatusBarBandBesideTheClock() {
        // The inner display's top safe area is the status bar's 82 pt.
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 455.5...495.5)
        let chrome = UnfoldedSplit.chrome(split, safeTop: 82)
        #expect(chrome.barTop == 30)
        #expect(chrome.barTop + UnfoldedSplit.paneTabBarHeight <= 82)
        // Just under the band, never on its edge.
        #expect(chrome.contentInset == 4)
        #expect(UnfoldedSplit.bottomFade(split) == UnfoldedSplit.paneEdgeFade)
    }

    @Test func aShortSafeAreaPushesTheScreensBelowTheBar() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        let chrome = UnfoldedSplit.chrome(split, safeTop: 20)
        #expect(chrome.barTop == UnfoldedSplit.paneTabBarGap)
        // The screens start a gap below the bar's bottom edge.
        #expect(20 + chrome.contentInset == chrome.barTop + UnfoldedSplit.paneTabBarHeight + UnfoldedSplit.paneTabBarGap)
    }
}
