/// An ordered list of query parameters, percent-encoded for the wire.
///
/// Keys such as `filter[country_code]` are written with their brackets percent-encoded
/// (`filter%5Bcountry_code%5D`), which servers decode to the same key. Everything except
/// RFC 3986 unreserved characters is encoded in both keys and values, so a leading `+` in an
/// E.164 number is sent as `%2B` and is not read back as a space.
struct TelnyxQuery: Sendable {
    private(set) var items: [(name: String, value: String)] = []

    var isEmpty: Bool {
        items.isEmpty
    }

    mutating func add(_ name: String, _ value: String?) {
        guard let value: String = value else {
            return
        }
        items.append((name, value))
    }

    mutating func add(_ name: String, _ value: Int?) {
        add(name, value.map { (number: Int) -> String in String(number) })
    }

    mutating func add(_ name: String, _ value: Bool?) {
        add(name, value.map { (flag: Bool) -> String in flag ? "true" : "false" })
    }

    mutating func add<Value: TelnyxOpenEnum>(_ name: String, _ value: Value?) {
        add(name, value?.rawValue)
    }

    /// The encoded query string, without the leading `?`.
    var encoded: String {
        items
            .map { (item: (name: String, value: String)) -> String in
                "\(TelnyxQuery.percentEncode(item.name))=\(TelnyxQuery.percentEncode(item.value))"
            }
            .joined(separator: "&")
    }

    /// Percent-encodes everything except `A-Z a-z 0-9 - . _ ~`.
    static func percentEncode(_ string: String) -> String {
        let hex: [Character] = Array("0123456789ABCDEF")
        var result: String = ""
        result.reserveCapacity(string.utf8.count)
        for byte: UInt8 in string.utf8 {
            let isUnreserved: Bool = (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39)
                || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
            if isUnreserved {
                result.append(Character(Unicode.Scalar(byte)))
            } else {
                result.append("%")
                result.append(hex[Int(byte >> 4)])
                result.append(hex[Int(byte & 0x0F)])
            }
        }
        return result
    }
}
