public struct AttendanceMember: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let gain: Int
    public let rank: Int
}
