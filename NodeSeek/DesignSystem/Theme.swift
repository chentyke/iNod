import SwiftUI

extension Color {
    static let seekGreen = Color("AccentColor")
    static let seekSurface = Color("ReadingSurface")
    static let seekButtonIcon = Color("ButtonIcon")
    static let seekButtonIconOnFill = Color("ButtonIconOnFill")
    static let seekButtonIconOnDark = Color(white: 0.82)
    static let seekCanvas = Color("Canvas")
    static let seekCard = Color("Card")
    static let seekTray = Color("Tray")
    static let seekInk = Color("Ink")
    static let seekOnInk = Color("OnInk")
    static let seekHairline = Color("Hairline")
    /// The Mac sidebar's highlight behind the open tab, which always draws its label in white:
    /// ink in light mode, a grey in dark mode where ink turns white.
    static let seekSidebarSelection = Color("SidebarSelection")

    static func categoryTint(_ id: String) -> Color {
        switch id {
        case "tech", "dev": .blue
        case "trade", "promotion": .orange
        case "info", "review": .indigo
        case "photo-share", "life": .teal
        case "expose": .red
        default: .seekGreen
        }
    }
}

extension View {
    func seekCanvas(margins: ReadableMargin = .replacesInset, in scroller: ReadableScroller = .list) -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
            .scrollContentBackground(.hidden).background(SeekCanvas())
            .readableContentMargins(margins, in: scroller)
    }

    func seekCard(padding: CGFloat = 20, radius: CGFloat = 24) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.seekCard, in: .rect(cornerRadius: radius))
    }

    func seekGroupedList() -> some View {
        listStyle(.insetGrouped).listSectionSpacing(20).seekCanvas()
    }
}
