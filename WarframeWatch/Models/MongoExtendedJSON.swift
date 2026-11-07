import Foundation

// MARK: - Safe OID Decoder
private enum OIDCodingKeys: String, CodingKey {
    case oid = "$oid"
}

public struct WFOID: Codable, Equatable, Hashable {
    public let id: String
    
    public init(_ id: String) {
        self.id = id
    }
    
    public init(from decoder: Decoder) throws {
        // 1. Try keyed container: {"$oid": "..."}
        if let container = try? decoder.container(keyedBy: OIDCodingKeys.self),
           let oid = try? container.decode(String.self, forKey: .oid) {
            self.id = oid
            return
        }
        
        // 2. Try single value: "string_id"
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            self.id = str
            return
        }
        
        // 3. Fallback: never fail decoding of an ID
        self.id = UUID().uuidString
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: OIDCodingKeys.self)
        try container.encode(id, forKey: .oid)
    }
}

// MARK: - Safe Date Decoder
private enum DateCodingKeys: String, CodingKey {
    case date = "$date"
}

private enum NumberLongCodingKeys: String, CodingKey {
    case numberLong = "$numberLong"
}

public struct WFDate: Codable, Equatable, Comparable, Hashable {
    public let date: Date
    
    public init(_ date: Date) {
        self.date = date
    }
    
    public init(timeIntervalSince1970 seconds: TimeInterval) {
        self.date = Date(timeIntervalSince1970: seconds)
    }
    
    public init(from decoder: Decoder) throws {
        // 1. Try keyed container: {"$date": ...}
        if let container = try? decoder.container(keyedBy: DateCodingKeys.self) {
            // Case A: {"$date": {"$numberLong": "1793984400000"}}
            if let nested = try? container.nestedContainer(keyedBy: NumberLongCodingKeys.self, forKey: .date),
               let numLongStr = try? nested.decode(String.self, forKey: .numberLong),
               let ms = Double(numLongStr) {
                self.date = Date(timeIntervalSince1970: ms / 1000.0)
                return
            }
            
            // Case B: {"$date": 1793984400000} (Double or Int)
            if let ms = try? container.decode(Double.self, forKey: .date) {
                let sec = ms > 1e11 ? ms / 1000.0 : ms
                self.date = Date(timeIntervalSince1970: sec)
                return
            }
            
            // Case C: {"$date": "1793984400000"} (String timestamp)
            if let str = try? container.decode(String.self, forKey: .date), let ms = Double(str) {
                let sec = ms > 1e11 ? ms / 1000.0 : ms
                self.date = Date(timeIntervalSince1970: sec)
                return
            }
            
            // Case D: {"$date": "2026-11-08T03:20:00Z"} (ISO8601 string)
            if let str = try? container.decode(String.self, forKey: .date),
               let iso = ISO8601DateFormatter().date(from: str) {
                self.date = iso
                return
            }
        }
        
        // 2. Try single value container: 1794053628 (Double / Int / String)
        if let single = try? decoder.singleValueContainer() {
            if let ms = try? single.decode(Double.self) {
                let sec = ms > 1e11 ? ms / 1000.0 : ms
                self.date = Date(timeIntervalSince1970: sec)
                return
            }
            if let str = try? single.decode(String.self) {
                if let ms = Double(str) {
                    let sec = ms > 1e11 ? ms / 1000.0 : ms
                    self.date = Date(timeIntervalSince1970: sec)
                    return
                }
                if let iso = ISO8601DateFormatter().date(from: str) {
                    self.date = iso
                    return
                }
            }
        }
        
        // 3. Fallback: Never fail decoding!
        self.date = Date()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DateCodingKeys.self)
        var nested = container.nestedContainer(keyedBy: NumberLongCodingKeys.self, forKey: .date)
        let msStr = String(Int64(date.timeIntervalSince1970 * 1000))
        try nested.encode(msStr, forKey: .numberLong)
    }
    
    public static func < (lhs: WFDate, rhs: WFDate) -> Bool {
        lhs.date < rhs.date
    }
}

// MARK: - Safe AnyCodable Helper
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() {
                self.value = NSNull()
                return
            } else if let bool = try? single.decode(Bool.self) {
                self.value = bool
                return
            } else if let int = try? single.decode(Int.self) {
                self.value = int
                return
            } else if let double = try? single.decode(Double.self) {
                self.value = double
                return
            } else if let string = try? single.decode(String.self) {
                self.value = string
                return
            }
        }
        if var arr = try? decoder.unkeyedContainer() {
            var values: [Any] = []
            while !arr.isAtEnd {
                if let v = try? arr.decode(AnyCodable.self) {
                    values.append(v.value)
                }
            }
            self.value = values
            return
        }
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            var dict: [String: Any] = [:]
            for k in keyed.allKeys {
                if let v = try? keyed.decode(AnyCodable.self, forKey: k) {
                    dict[k.stringValue] = v.value
                }
            }
            self.value = dict
            return
        }
        self.value = NSNull()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        default:
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) { return nil }
}
