import Foundation

/// Custom date decoder handling MongoDB Extended JSON format, Unix milliseconds, and Unix seconds.
public struct WFDate: Codable, Equatable, Comparable, Hashable {
    public let date: Date
    
    public init(_ date: Date) {
        self.date = date
    }
    
    public init(timeIntervalSince1970 seconds: TimeInterval) {
        self.date = Date(timeIntervalSince1970: seconds)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // 1. Try decoding extended JSON: {"$date": {"$numberLong": "12345"}} or {"$date": 12345}
        if let dict = try? container.decode([String: AnyCodable].self),
           let dateVal = dict["$date"] {
            if let numLong = (dateVal.value as? [String: Any])?["$numberLong"] as? String,
               let ms = Double(numLong) {
                self.date = Date(timeIntervalSince1970: ms / 1000.0)
                return
            } else if let ms = dateVal.value as? Double {
                self.date = Date(timeIntervalSince1970: ms / 1000.0)
                return
            } else if let str = dateVal.value as? String, let ms = Double(str) {
                self.date = Date(timeIntervalSince1970: ms / 1000.0)
                return
            }
        }
        
        // 2. Try decoding as Double / Int timestamp directly
        if let timestamp = try? container.decode(Double.self) {
            let seconds = timestamp > 1e11 ? timestamp / 1000.0 : timestamp
            self.date = Date(timeIntervalSince1970: seconds)
            return
        }
        
        // 3. Try string timestamp
        if let str = try? container.decode(String.self), let timestamp = Double(str) {
            let seconds = timestamp > 1e11 ? timestamp / 1000.0 : timestamp
            self.date = Date(timeIntervalSince1970: seconds)
            return
        }
        
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Cannot decode WFDate from provided value"
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Int64(date.timeIntervalSince1970 * 1000))
    }
    
    public static func < (lhs: WFDate, rhs: WFDate) -> Bool {
        lhs.date < rhs.date
    }
}

/// Custom ID decoder handling MongoDB Extended JSON `{"$oid": "..."}` or string id
public struct WFOID: Codable, Equatable, Hashable {
    public let id: String
    
    public init(_ id: String) {
        self.id = id
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self), let oid = dict["$oid"] {
            self.id = oid
            return
        }
        if let str = try? container.decode(String.self) {
            self.id = str
            return
        }
        self.id = UUID().uuidString
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(["$oid": id])
    }
}

/// Helper for heterogeneous JSON values in extended JSON structures
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported AnyCodable value"
            )
        }
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
