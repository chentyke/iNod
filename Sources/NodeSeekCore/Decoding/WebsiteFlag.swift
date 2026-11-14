import Foundation

@propertyWrapper public struct WebsiteFlag: Decodable, Sendable {
    public var wrappedValue: Bool?
    public init(wrappedValue: Bool? = nil) { self.wrappedValue = wrappedValue }
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { wrappedValue = nil }
        else if let boolean = try? value.decode(Bool.self) { wrappedValue = boolean }
        else if let number = try? value.decode(Int.self),number == 0 || number == 1 { wrappedValue = number == 1 }
        else { throw DecodingError.dataCorruptedError(in:value,debugDescription:"Expected a boolean or 0/1 website flag") }
    }
}
public extension KeyedDecodingContainer {
    func decode(_ type: WebsiteFlag.Type,forKey key: Key) throws -> WebsiteFlag { try decodeIfPresent(type,forKey:key) ?? WebsiteFlag() }
}
@propertyWrapper public struct WebsiteBool: Decodable, Sendable {
    public var wrappedValue: Bool
    public init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }
    public init(from decoder: any Decoder) throws {
        let flag = try WebsiteFlag(from:decoder)
        guard let value = flag.wrappedValue else { throw DecodingError.valueNotFound(Bool.self,.init(codingPath:decoder.codingPath,debugDescription:"Missing website flag")) }
        wrappedValue = value
    }
}
