public struct AttendanceBoard: Decodable, Sendable {
    public let gain: Int?
    public let order: Int?
    public let total: Int
    public var items: [AttendanceMember]
    public let hasNext: Bool
}
