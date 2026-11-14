import Foundation

public enum ANSIColor: Equatable, Sendable {
    case indexed(Int)
    case rgb(Int, Int, Int)
}

public struct ANSIStyle: Equatable, Sendable {
    public var foreground: ANSIColor?
    public var background: ANSIColor?
    public var bold = false
    public var italic = false
    public var underlined = false

    mutating func apply(_ values: [Int]) {
        var index = 0
        while index < values.count {
            let value = values[index]
            switch value {
            case 0: self = ANSIStyle()
            case 1: bold = true
            case 3: italic = true
            case 4: underlined = true
            case 22: bold = false
            case 23: italic = false
            case 24: underlined = false
            case 30...37: foreground = .indexed(value - 30)
            case 40...47: background = .indexed(value - 40)
            case 90...97: foreground = .indexed(value - 90 + 8)
            case 100...107: background = .indexed(value - 100 + 8)
            case 39: foreground = nil
            case 49: background = nil
            case 38, 48:
                var color: ANSIColor?
                if index + 2 < values.count, values[index + 1] == 5 {
                    color = .indexed(values[index + 2]); index += 2
                } else if index + 4 < values.count, values[index + 1] == 2 {
                    color = .rgb(values[index + 2], values[index + 3], values[index + 4]); index += 4
                }
                if value == 38 { foreground = color } else { background = color }
            default: break
            }
            index += 1
        }
    }
}

public struct ANSIRun: Equatable, Sendable {
    public var text: String
    public let style: ANSIStyle
}

public enum ANSIText {
    public static func parse(_ text: String) -> [ANSIRun] {
        let scalars = Array(text.unicodeScalars)
        var runs: [ANSIRun] = []
        var style = ANSIStyle()
        var buffer = ""
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            if runs.last?.style == style { runs[runs.count - 1].text += buffer }
            else { runs.append(ANSIRun(text: buffer, style: style)) }
            buffer = ""
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B {
                flush()
                index += 1
                guard index < scalars.count else { break }
                if scalars[index] == "[" {
                    index += 1
                    let start = index
                    while index < scalars.count, !(0x40...0x7E).contains(scalars[index].value) { index += 1 }
                    if index < scalars.count, scalars[index] == "m" {
                        let parameters = String(String.UnicodeScalarView(scalars[start..<index]))
                        style.apply(parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 })
                    }
                } else if scalars[index] == "]" {
                    // OSC sequences carry terminal metadata such as link targets, not visible text.
                    index += 1
                    while index < scalars.count, scalars[index].value != 7 {
                        if scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1] == "\\" {
                            index += 1; break
                        }
                        index += 1
                    }
                }
            } else if scalar.value == 8 {
                if !buffer.isEmpty { buffer.removeLast() }
                else if !runs.isEmpty {
                    runs[runs.count - 1].text.removeLast()
                    if runs.last?.text.isEmpty == true { runs.removeLast() }
                }
            } else if scalar.value >= 32 || scalar == "\n" || scalar == "\t" {
                buffer.unicodeScalars.append(scalar)
            }
            index += 1
        }
        flush()
        return runs
    }
}
