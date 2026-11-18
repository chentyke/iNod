/// Geometry rules for the iPad community tab's side-by-side feed and thread layout.
public enum FeedSplitLayout: Sendable {
    /// The widest a card grows before centring in a column.
    public static let readableWidth: Double = 760
    /// The gap between a card and its column edge.
    public static let gutter: Double = 16
    /// Hairline rule between the feed column and the thread column.
    public static let dividerWidth: Double = 0.5
    /// Narrower than this (Slide Over or half-screen Split View), iPad falls back to one column.
    public static let minimumSplitWidth: Double = 720
    /// Width bounds for the left feed column when split mode is active.
    public static let minimumFeedPaneWidth: Double = 336
    public static let maximumFeedPaneWidth: Double = 400
    public static let feedPaneFraction: Double = 0.38

    /// Whether a feed container of `width` points splits into list and reader panes.
    public static func usesSplit(width: Double, supportsSplit: Bool, isCompact: Bool) -> Bool {
        supportsSplit && !isCompact && width >= minimumSplitWidth
    }

    /// Width of the left feed pane inside a split container of `totalWidth` points.
    public static func feedPaneWidth(forTotalWidth totalWidth: Double) -> Double {
        let proportional = (totalWidth * feedPaneFraction).rounded(.down)
        return min(maximumFeedPaneWidth, max(minimumFeedPaneWidth, proportional))
    }

    /// Remaining width for the right thread reader pane inside `totalWidth` points.
    public static func detailPaneWidth(forTotalWidth totalWidth: Double) -> Double {
        max(0, totalWidth - feedPaneWidth(forTotalWidth: totalWidth) - dividerWidth)
    }
}
