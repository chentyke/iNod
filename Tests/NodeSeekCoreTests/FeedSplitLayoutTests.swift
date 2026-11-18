import Testing
@testable import NodeSeekCore

@Test func feedSplitActivatesOnlyOnWideSupportedContainers() {
    // Full-screen iPad mini, 11-inch and 13-inch portrait & landscape widths split into two panes.
    #expect(FeedSplitLayout.usesSplit(width: 744, supportsSplit: true, isCompact: false))
    #expect(FeedSplitLayout.usesSplit(width: 820, supportsSplit: true, isCompact: false))
    #expect(FeedSplitLayout.usesSplit(width: 1032, supportsSplit: true, isCompact: false))
    #expect(FeedSplitLayout.usesSplit(width: 1376, supportsSplit: true, isCompact: false))
    #expect(FeedSplitLayout.usesSplit(width: 720, supportsSplit: true, isCompact: false))

    // Slide Over, narrow Split View, compact size classes, iPhone and Mac Catalyst stay single-column.
    #expect(!FeedSplitLayout.usesSplit(width: 719, supportsSplit: true, isCompact: false))
    #expect(!FeedSplitLayout.usesSplit(width: 678, supportsSplit: true, isCompact: false))
    #expect(!FeedSplitLayout.usesSplit(width: 375, supportsSplit: true, isCompact: false))
    #expect(!FeedSplitLayout.usesSplit(width: 1032, supportsSplit: true, isCompact: true))
    #expect(!FeedSplitLayout.usesSplit(width: 1376, supportsSplit: false, isCompact: false))
}

@Test func feedSplitPaneWidthsClampAndPartitionContainerCleanly() {
    // Narrower iPad portrait clamps the feed column to its 336pt floor.
    #expect(FeedSplitLayout.feedPaneWidth(forTotalWidth: 744) == 336)
    #expect(FeedSplitLayout.detailPaneWidth(forTotalWidth: 744) == 407.5)
    #expect(FeedSplitLayout.feedPaneWidth(forTotalWidth: 820) == 336)
    #expect(FeedSplitLayout.detailPaneWidth(forTotalWidth: 820) == 483.5)

    // 13-inch iPad portrait scales proportionally to 392pt.
    #expect(FeedSplitLayout.feedPaneWidth(forTotalWidth: 1032) == 392)
    #expect(FeedSplitLayout.detailPaneWidth(forTotalWidth: 1032) == 639.5)

    // Landscape caps the feed column at 400pt and gives the rest to the reader column.
    #expect(FeedSplitLayout.feedPaneWidth(forTotalWidth: 1056) == 400)
    #expect(FeedSplitLayout.detailPaneWidth(forTotalWidth: 1056) == 655.5)
    #expect(FeedSplitLayout.feedPaneWidth(forTotalWidth: 1376) == 400)
    #expect(FeedSplitLayout.detailPaneWidth(forTotalWidth: 1376) == 975.5)

    for totalWidth in [720.0, 744.0, 820.0, 900.0, 1032.0, 1180.0, 1376.0] {
        let sum = FeedSplitLayout.feedPaneWidth(forTotalWidth: totalWidth)
            + FeedSplitLayout.dividerWidth
            + FeedSplitLayout.detailPaneWidth(forTotalWidth: totalWidth)
        #expect(sum == totalWidth)
    }
}
