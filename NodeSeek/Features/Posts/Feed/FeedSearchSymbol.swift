import SwiftUI

struct FeedSearchSymbol: Shape {
    enum Alternate {
        case close
        case add
    }

    let alternate: Alternate
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(progress, 0), 1)
        let center = UnitPoint(x: 0.43, y: 0.43)
        let radius: CGFloat = 0.31
        let jointAngle = CGFloat.pi / 4
        let diagonalOffset = radius * cos(jointAngle)
        let joint = UnitPoint(x: center.x + diagonalOffset, y: center.y + diagonalOffset)

        func point(from start: UnitPoint, to end: UnitPoint, amount: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (start.x + (end.x - start.x) * amount) * rect.width,
                    y: rect.minY + (start.y + (end.y - start.y) * amount) * rect.height)
        }

        let handleStart = alternate == .close ? UnitPoint(x: 0.20, y: 0.20) : UnitPoint(x: 0.14, y: 0.50)
        let handleEnd = alternate == .close ? UnitPoint(x: 0.80, y: 0.80) : UnitPoint(x: 0.86, y: 0.50)
        let handleProgress = progress * (2 - progress)
        var path = Path()
        path.move(to: point(from: joint, to: handleStart, amount: handleProgress))
        path.addLine(to: point(from: UnitPoint(x: 0.88, y: 0.88), to: handleEnd, amount: handleProgress))

        // The ring's two halves unfold on opposite sides of the handle.
        for direction: CGFloat in [-1, 1] {
            let end = alternate == .close
                ? UnitPoint(x: 0.50 - direction * 0.30, y: 0.50 + direction * 0.30)
                : UnitPoint(x: 0.50, y: 0.50 + direction * 0.36)
            let step = direction * .pi / 2
            let tangentLength = radius * (4 / 3) * tan(step / 4)

            func linePoint(_ fraction: CGFloat) -> UnitPoint {
                UnitPoint(x: 0.50 + (end.x - 0.50) * fraction, y: 0.50 + (end.y - 0.50) * fraction)
            }

            func ringPoint(_ angle: CGFloat, tangent: CGFloat = 0) -> UnitPoint {
                UnitPoint(x: center.x + radius * cos(angle) - tangent * sin(angle),
                          y: center.y + radius * sin(angle) + tangent * cos(angle))
            }

            path.move(to: point(from: joint, to: .center, amount: progress))
            for quarter in 0..<2 {
                let angle = jointAngle + CGFloat(quarter) * step
                let fraction = CGFloat(quarter) / 2
                path.addCurve(
                    to: point(from: ringPoint(angle + step), to: linePoint(fraction + 1 / 2), amount: progress),
                    control1: point(from: ringPoint(angle, tangent: tangentLength), to: linePoint(fraction + 1 / 6), amount: progress),
                    control2: point(from: ringPoint(angle + step, tangent: -tangentLength), to: linePoint(fraction + 1 / 3), amount: progress)
                )
            }
        }

        return path
    }
}
