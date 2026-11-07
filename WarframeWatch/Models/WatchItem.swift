import Foundation

/// Item starred by user to keep in watchlist and schedule expiration reminders.
public struct WatchItem: Codable, Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let section: String
    public let expiry: Date?
    public let starredAt: Date
    public var isReminderEnabled: Bool
    
    public init(
        key: String,
        label: String,
        section: String,
        expiry: Date?,
        starredAt: Date = Date(),
        isReminderEnabled: Bool = true
    ) {
        self.key = key
        self.label = label
        self.section = section
        self.expiry = expiry
        self.starredAt = starredAt
        self.isReminderEnabled = isReminderEnabled
    }
    
    public var isExpiringSoon: Bool {
        guard let exp = expiry else { return false }
        let diff = exp.timeIntervalSince(Date())
        return diff > 0 && diff <= 1800 // 30 minutes
    }
    
    public var isExpired: Bool {
        guard let exp = expiry else { return false }
        return exp < Date()
    }
}
