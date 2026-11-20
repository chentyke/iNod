import SwiftUI
enum LedgerKind: Hashable {
    case chicken, stardust
    var title: String { self == .chicken ? "鸡腿明细" : "星尘明细" }
    var symbol: ImageResource { self == .chicken ? .inkDrumstick : .inkStardust }
}
