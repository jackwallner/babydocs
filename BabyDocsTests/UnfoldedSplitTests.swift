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
}
