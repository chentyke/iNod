import Foundation
import CoreGraphics

public struct StickerAnimation: Sendable {
    let frames: [CGImage]
    let durations: [TimeInterval]

    public var isAnimated: Bool { frames.count > 1 }

    public func frame(at date: Date, reducingMotion: Bool) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        guard !reducingMotion, frames.count > 1 else { return frames.first }
        let total = durations.reduce(0, +)
        guard total > 0 else { return frames.first }
        var position = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        for (index, duration) in durations.enumerated() {
            if position < duration { return frames[index] }
            position -= duration
        }
        return frames.first
    }
}
