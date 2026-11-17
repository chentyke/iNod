import CoreGraphics
import Foundation
import Testing
@testable import NodeSeekClient

struct StickerAnimationTests {
    @Test func selectsFramesAtTheirBoundariesAndLoops() throws {
        let frames = try (0..<3).map { _ in try makeFrame() }
        let animation = StickerAnimation(frames: frames, durations: [0.25, 0.5, 0.125])
        let samples: [(offset: TimeInterval, frameIndex: Int)] = [
            (-0.125, 0),
            (0, 0),
            (0.234375, 0),
            (0.25, 1),
            (0.734375, 1),
            (0.75, 2),
            (0.859375, 2),
            (0.875, 0),
            (1.125, 1),
            (1.625, 2),
            (1.75, 0)
        ]

        #expect(animation.isAnimated)
        for (offset, frameIndex) in samples {
            let date = Date(timeIntervalSinceReferenceDate: offset)
            #expect(animation.frame(at: date, reducingMotion: false) === frames[frameIndex], "Offset: \(offset)")
        }
    }

    @Test func handlesEmptyAndSingleFrameAnimations() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1)
        let empty = StickerAnimation(frames: [], durations: [])
        let frame = try makeFrame()
        let still = StickerAnimation(frames: [frame], durations: [0.25])

        #expect(!empty.isAnimated)
        #expect(empty.frame(at: date, reducingMotion: false) == nil)
        #expect(!still.isAnimated)
        #expect(still.frame(at: date, reducingMotion: false) === frame)
    }

    @Test func showsTheFirstFrameWithReduceMotion() throws {
        let first = try makeFrame()
        let second = try makeFrame()
        let animation = StickerAnimation(frames: [first, second], durations: [0.25, 0.5])
        let date = Date(timeIntervalSinceReferenceDate: 0.5)

        #expect(animation.frame(at: date, reducingMotion: true) === first)
    }

    @Test func showsTheFirstFrameWhenTotalDurationIsZero() throws {
        let first = try makeFrame()
        let second = try makeFrame()
        let animation = StickerAnimation(frames: [first, second], durations: [0, 0])
        let date = Date(timeIntervalSinceReferenceDate: 1)

        #expect(animation.frame(at: date, reducingMotion: false) === first)
    }

    private func makeFrame() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                            bitmapInfo: CGImageAlphaInfo.none.rawValue))
        return try #require(context.makeImage())
    }
}
