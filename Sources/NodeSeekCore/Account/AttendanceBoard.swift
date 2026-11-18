public struct AttendanceBoard: Decodable, Sendable {
    public let gain: Int?
    public let order: Int?
    public let createdAt: String?
    public let total: Int
    public var items: [AttendanceMember]
    public let hasNext: Bool
}
