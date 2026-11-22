import Foundation

/// ISO 8601 parsing and formatting for Telnyx timestamps.
///
/// Written by hand rather than with `DateFormatter` / `ISO8601DateFormatter` so behaviour is the
/// same on macOS and Linux and nothing non-`Sendable` is shared between tasks.
enum TelnyxDate {
    /// Parses `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM|±HHMM)`; the fraction may have any number of digits.
    static func parse(_ string: String) -> Date? {
        let bytes: [UInt8] = Array(string.utf8)
        var index: Int = 0

        func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else {
                return nil
            }
            var value: Int = 0
            for offset: Int in 0..<count {
                let byte: UInt8 = bytes[index + offset]
                guard byte >= 0x30, byte <= 0x39 else {
                    return nil
                }
                value = value * 10 + Int(byte - 0x30)
            }
            index += count
            return value
        }

        func expect(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else {
                return false
            }
            index += 1
            return true
        }

        guard let year: Int = digits(4), expect(0x2D),
              let month: Int = digits(2), expect(0x2D),
              let day: Int = digits(2)
        else {
            return nil
        }
        guard index < bytes.count, bytes[index] == 0x54 || bytes[index] == 0x74 || bytes[index] == 0x20 else {
            return nil
        }
        index += 1
        guard let hour: Int = digits(2), expect(0x3A),
              let minute: Int = digits(2), expect(0x3A),
              let second: Int = digits(2)
        else {
            return nil
        }

        var fraction: Double = 0
        if index < bytes.count, bytes[index] == 0x2E || bytes[index] == 0x2C {
            index += 1
            var scale: Double = 0.1
            var sawDigit: Bool = false
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                fraction += Double(bytes[index] - 0x30) * scale
                scale /= 10
                index += 1
                sawDigit = true
            }
            guard sawDigit else {
                return nil
            }
        }

        var offsetSeconds: Int = 0
        guard index < bytes.count else {
            return nil
        }
        let zoneByte: UInt8 = bytes[index]
        if zoneByte == 0x5A || zoneByte == 0x7A {
            index += 1
        } else if zoneByte == 0x2B || zoneByte == 0x2D {
            index += 1
            guard let offsetHours: Int = digits(2) else {
                return nil
            }
            _ = expect(0x3A)
            guard let offsetMinutes: Int = digits(2) else {
                return nil
            }
            let magnitude: Int = offsetHours * 3600 + offsetMinutes * 60
            offsetSeconds = zoneByte == 0x2B ? magnitude : -magnitude
        } else {
            return nil
        }
        guard index == bytes.count else {
            return nil
        }
        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
        else {
            return nil
        }

        let days: Int = daysFromCivil(year: year, month: month, day: day)
        let seconds: Int = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    /// Formats as `YYYY-MM-DDTHH:MM:SSZ` in UTC (whole seconds).
    static func format(_ date: Date) -> String {
        let total: Int = Int(date.timeIntervalSince1970.rounded(.down))
        var days: Int = total / 86_400
        var secondsOfDay: Int = total % 86_400
        if secondsOfDay < 0 {
            secondsOfDay += 86_400
            days -= 1
        }
        let civil: (year: Int, month: Int, day: Int) = civilFromDays(days)
        let hour: Int = secondsOfDay / 3600
        let minute: Int = (secondsOfDay % 3600) / 60
        let second: Int = secondsOfDay % 60
        return "\(pad(civil.year, 4))-\(pad(civil.month, 2))-\(pad(civil.day, 2))T\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2))Z"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text: String = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    // Howard Hinnant's days_from_civil / civil_from_days (proleptic Gregorian).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let adjustedYear: Int = month <= 2 ? year - 1 : year
        let era: Int = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra: Int = adjustedYear - era * 400
        let shiftedMonth: Int = month > 2 ? month - 3 : month + 9
        let dayOfYear: Int = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra: Int = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let shifted: Int = days + 719_468
        let era: Int = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra: Int = shifted - era * 146_097
        let yearOfEra: Int = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear: Int = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth: Int = (5 * dayOfYear + 2) / 153
        let day: Int = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month: Int = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year: Int = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}

enum TelnyxJSON {
    /// A decoder for Telnyx responses: ISO 8601 dates with or without fractional seconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { (decoder: any Decoder) throws -> Date in
            let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()
            let string: String = try container.decode(String.self)
            guard let date: Date = TelnyxDate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 date")
            }
            return date
        }
        return decoder
    }

    /// An encoder for Telnyx request bodies: ISO 8601 UTC dates, sorted keys for stable output.
    static func makeEncoder() -> JSONEncoder {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { (date: Date, encoder: any Encoder) throws in
            var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
            try container.encode(TelnyxDate.format(date))
        }
        return encoder
    }
}
