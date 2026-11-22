/// A request field that can carry a value or an explicit JSON `null`.
///
/// Use it as an optional property (`TelnyxNullable<String>?`) to get three states:
/// `nil` omits the key, `.null` sends `"key": null`, and `.value(x)` sends `"key": x`.
public enum TelnyxNullable<Wrapped: Encodable & Sendable>: Encodable, Sendable {
    /// Send the value.
    case value(Wrapped)
    /// Send an explicit JSON `null`.
    case null

    public func encode(to encoder: any Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        switch self {
        case .value(let wrapped):
            try container.encode(wrapped)
        case .null:
            try container.encodeNil()
        }
    }
}

extension TelnyxNullable: Equatable where Wrapped: Equatable {}
