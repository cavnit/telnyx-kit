/// A string value decoded from Telnyx whose set of values may grow.
///
/// Types conforming to this protocol are string-backed structs with static constants for the
/// documented values. Any other string decodes without error and is kept in `rawValue`, so a
/// value Telnyx adds later does not break decoding. Compare with the constants
/// (`status == .active`) or switch on `rawValue`.
public protocol TelnyxOpenEnum: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible where RawValue == String
{
    init(rawValue: String)
}

extension TelnyxOpenEnum {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: any Decoder) throws {
        let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()
        let value: String = try container.decode(String.self)
        self.init(rawValue: value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}
