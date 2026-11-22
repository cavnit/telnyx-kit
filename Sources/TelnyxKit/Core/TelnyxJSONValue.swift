/// An arbitrary JSON value, used where Telnyx's payload shape is not documented closely enough
/// to model, and to keep the raw payload of webhook events this package does not know.
public enum TelnyxJSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([TelnyxJSONValue])
    case object([String: TelnyxJSONValue])

    public init(from decoder: any Decoder) throws {
        let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value: Bool = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value: Int = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value: Double = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value: String = try? container.decode(String.self) {
            self = .string(value)
        } else if let value: [TelnyxJSONValue] = try? container.decode([TelnyxJSONValue].self) {
            self = .array(value)
        } else if let value: [String: TelnyxJSONValue] = try? container.decode([String: TelnyxJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// The member named `key`, if this is an object that has it.
    public subscript(key: String) -> TelnyxJSONValue? {
        guard case .object(let object) = self else {
            return nil
        }
        return object[key]
    }

    /// The string, if this is a string.
    public var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }
}
