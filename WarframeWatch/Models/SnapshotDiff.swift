import Foundation

/// Metric change in a snapshot comparison
public struct MetricChange: Codable, Identifiable, Hashable {
    public var id: String { "\(label)_\(fromValue)_\(toValue)" }
    public let label: String
    public let fromValue: String
    public let toValue: String
}

/// Changes detected in a specific category (e.g. 虚空裂隙, 限时警报, 入侵事件)
public struct DiffGroup: Codable, Identifiable, Hashable {
    public var id: String { groupName }
    public let groupName: String
    public var added: [String]
    public var removed: [String]
    public var changed: [MetricChange]
    
    public var totalChanges: Int {
        added.count + removed.count + changed.count
    }
}

/// Fingerprint of a WorldState snapshot used for diffing
public struct WorldStateFingerprint: Codable {
    public let timestamp: Date
    public let sets: [String: [String: String]] // [Group: [Key: Label]]
    public let metrics: [String: [String: String]] // [Group: [Key: MetricValue]]
}
