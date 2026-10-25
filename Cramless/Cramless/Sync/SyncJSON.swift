import Foundation

/// Any JSON value. Sync rows are built from these, so a nil field is sent as an explicit `null` (PostgREST updates
/// only the keys it receives) and a model's Codable blob is embedded as JSON, not base64.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? c.decode(Double.self) {
            self = .double(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .int(let value): try c.encode(value)
        case .double(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    // MARK: Building

    static func text(_ value: String?) -> JSONValue { value.map { JSONValue.string($0) } ?? .null }
    static func integer(_ value: Int) -> JSONValue { .int(Int64(value)) }
    static func integer(_ value: Int?) -> JSONValue { value.map { .int(Int64($0)) } ?? .null }
    static func number(_ value: Double?) -> JSONValue {
        guard let value, value.isFinite else { return .null }
        return .double(value)
    }
    static func date(_ value: Date?) -> JSONValue { value.map { .string(SupabaseDate.format($0)) } ?? .null }
    static func uuid(_ value: UUID?) -> JSONValue { value.map { .string($0.uuidString.lowercased()) } ?? .null }

    /// A Codable blob (`…Data` on a model) as embedded JSON; unreadable or missing data is `null`.
    static func blob(_ data: Data?) -> JSONValue {
        guard let data, let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return value
    }

    // MARK: Reading

    var isNull: Bool { if case .null = self { true } else { false } }

    var stringValue: String? { if case .string(let s) = self { s } else { nil } }

    var doubleValue: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        case .string(let s): Double(s)
        default: nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): Int(exactly: i)
        case .double(let d): d.isFinite ? Int(d) : nil
        case .string(let s): Int(s)
        default: nil
        }
    }

    var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }

    /// The value re-encoded for a model's blob attribute; nil for `null`.
    var blobData: Data? {
        if isNull { return nil }
        return try? JSONValue.sortedEncoder.encode(self)
    }

    private static let sortedEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

/// One table row as PostgREST sends and receives it: snake_case columns to JSON values.
typealias SyncRow = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? { self[key]?.stringValue }
    func double(_ key: String) -> Double? { self[key]?.doubleValue }
    func int(_ key: String) -> Int? { self[key]?.intValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func date(_ key: String) -> Date? { self[key]?.stringValue.flatMap(SupabaseDate.parse) }
    func uuid(_ key: String) -> UUID? { self[key]?.stringValue.flatMap { UUID(uuidString: $0) } }
    func blob(_ key: String) -> Data? { self[key]?.blobData }
}

/// Timestamps as Postgres speaks them: ISO 8601 with up to six fractional digits and a `Z` or `±hh:mm` offset
/// (`2026-10-22T09:00:00.123456+00:00`). Postgres keeps microseconds, so sync compares times at that grain
/// (`micros`): a row read back from the server equals the device's own copy instead of looking newer.
enum SupabaseDate {
    /// Microseconds since 1970, rounded: the grain Postgres stores.
    static func micros(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    static func format(_ date: Date) -> String {
        let total = micros(date)
        let whole = total >= 0 ? total / 1_000_000 : (total - 999_999) / 1_000_000
        let fraction = total - whole * 1_000_000
        let c = Calendar.gregorianUTC.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                     from: Date(timeIntervalSince1970: Double(whole)))
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, Int(fraction))
    }

    static func parse(_ text: String) -> Date? {
        let chars = Array(text.utf8)
        func number(_ start: Int, _ length: Int) -> Int? {
            guard start + length <= chars.count else { return nil }
            var value = 0
            for i in start..<(start + length) {
                let ch = chars[i]
                guard ch >= 48, ch <= 57 else { return nil }
                value = value * 10 + Int(ch - 48)
            }
            return value
        }
        // yyyy-MM-dd[T ]HH:mm[:ss]
        guard chars.count >= 16, let year = number(0, 4), chars[4] == 45, let month = number(5, 2), chars[7] == 45,
              let day = number(8, 2), chars[10] == 84 || chars[10] == 32, let hour = number(11, 2), chars[13] == 58,
              let minute = number(14, 2) else { return nil }
        var index = 16
        var second = 0
        if index < chars.count, chars[index] == 58 {
            guard let s = number(index + 1, 2) else { return nil }
            second = s
            index += 3
        }
        var fractionMicros: Int64 = 0
        if index < chars.count, chars[index] == 46 {
            index += 1
            var digits = 0
            while index < chars.count, chars[index] >= 48, chars[index] <= 57 {
                if digits < 6 {
                    fractionMicros = fractionMicros * 10 + Int64(chars[index] - 48)
                } else if digits == 6, chars[index] >= 53 {
                    fractionMicros += 1 // round half up at the seventh digit
                }
                digits += 1
                index += 1
            }
            guard digits > 0 else { return nil }
            for _ in min(digits, 6)..<6 { fractionMicros *= 10 }
        }
        var offset = 0
        if index < chars.count {
            let sign = chars[index]
            if sign == 90 || sign == 122 { // Z
                index += 1
            } else if sign == 43 || sign == 45 { // + or -
                guard let oh = number(index + 1, 2) else { return nil }
                var om = 0
                var next = index + 3
                if next < chars.count, chars[next] == 58 { next += 1 }
                if let m = number(next, 2) { om = m; next += 2 }
                offset = (oh * 3600 + om * 60) * (sign == 45 ? -1 : 1)
                index = next
            } else {
                return nil
            }
        }
        guard index == chars.count else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        guard let base = Calendar.gregorianUTC.date(from: comps) else { return nil }
        let wholeSeconds = Int64(base.timeIntervalSince1970.rounded()) - Int64(offset)
        return Date(timeIntervalSince1970: Double(wholeSeconds * 1_000_000 + fractionMicros) / 1_000_000)
    }
}
