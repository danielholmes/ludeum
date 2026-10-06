import Foundation

/// A raw JSON value, used to keep external records verbatim.
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] } else { return nil }
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] } else { return nil }
    }

    public var string: String? { if case .string(let s) = self { return s } else { return nil } }
    public var number: Double? { if case .number(let n) = self { return n } else { return nil } }
    public var int: Int? { number.map { Int($0) } }
    public var array: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }

    /// Reads a record. Through `JSONSerialization`, not `init(from:)`: a record is tens of kilobytes, and trying each
    /// kind of value in turn throws and discards an error or four for every value in it.
    static func decode(_ data: Data) throws -> JSONValue {
        try JSONValue(read: try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
    }

    private init(read value: Any) throws {
        switch value {
        case is NSNull: self = .null
        // A JSON `true` or `false` comes back as the one number that's a `CFBoolean`.
        case let n as NSNumber: self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(try a.map(JSONValue.init(read:)))
        case let o as [String: Any]: self = .object(try o.mapValues(JSONValue.init(read:)))
        default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a JSON value: \(type(of: value))"))
        }
    }
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
