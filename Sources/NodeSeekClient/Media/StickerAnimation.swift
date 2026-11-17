import Foundation
import CoreGraphics

public struct StickerAnimation: Sendable {
    let frames: [CGImage]
    let durations: [TimeInterval]
    private let totalDuration: TimeInterval

    init(frames: [CGImage], durations: [TimeInterval]) {
        self.frames = frames
        self.durations = durations
        self.totalDuration = durations.reduce(0, +)
    }

    public var isAnimated: Bool { frames.count > 1 }

    public func frame(at date: Date, reducingMotion: Bool) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        guard !reducingMotion, frames.count > 1 else { return frames.first }
        guard totalDuration > 0 else { return frames.first }
        var position = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: totalDuration)
        for (index, duration) in durations.enumerated() {
            if position < duration { return frames[index] }
            position -= duration
        }
        return frames.first
    }
}
