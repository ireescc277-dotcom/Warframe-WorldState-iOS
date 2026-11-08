import Foundation

/// Current arbitration, as published by `api.warframestat.us/pc/arbitration`.
///
/// Arbitration never appears in DE's own worldState feed, so this third-party
/// mirror is the only place a running arbitration can be read from. We join on
/// `nodeKey` (the star-chart node id, e.g. `SolNode108`) rather than on `node`,
/// because `node` is a localised display string while `nodeKey` is stable.
public struct ArbitrationInfo: Decodable {
    public let node: String?
    public let nodeKey: String?
    public let type: String?
    public let typeKey: String?
    public let enemy: String?
    public let activation: String?
    public let expiry: String?
    public let expired: Bool?

    public init(
        node: String? = nil,
        nodeKey: String? = nil,
        type: String? = nil,
        typeKey: String? = nil,
        enemy: String? = nil,
        activation: String? = nil,
        expiry: String? = nil,
        expired: Bool? = nil
    ) {
        self.node = node
        self.nodeKey = nodeKey
        self.type = type
        self.typeKey = typeKey
        self.enemy = enemy
        self.activation = activation
        self.expiry = expiry
        self.expired = expired
    }

    /// The feed keeps returning a stub whenever nothing is running: node
    /// `SolNode000`, type `Unknown`, expiry year 275760. Treat that as "no
    /// arbitration" instead of surfacing a hit on a nonexistent node.
    public var isPlaceholder: Bool {
        if expired == true { return true }
        guard let nodeKey, !nodeKey.isEmpty else { return true }
        if nodeKey == "SolNode000" { return true }
        if (type ?? "Unknown") == "Unknown" { return true }
        return false
    }

    public var expiryDate: Date? {
        guard let expiry else { return nil }
        return ArbitrationInfo.parse(expiry)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }
}
