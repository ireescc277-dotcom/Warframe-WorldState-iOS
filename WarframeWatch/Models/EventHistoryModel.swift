import Foundation

public struct EventHistoryStats: Codable {
    public let targetId: String
    public var totalSeenCount: Int
    public var firstSeenDate: Date?
    public var lastSeenDate: Date?
    public var intervals: [TimeInterval] // in seconds
    
    public init(targetId: String, totalSeenCount: Int = 0, firstSeenDate: Date? = nil, lastSeenDate: Date? = nil, intervals: [TimeInterval] = []) {
        self.targetId = targetId
        self.totalSeenCount = totalSeenCount
        self.firstSeenDate = firstSeenDate
        self.lastSeenDate = lastSeenDate
        self.intervals = intervals
    }
    
    public var meanInterval: TimeInterval {
        if intervals.isEmpty {
            // Baseline priors based on historical DE game data
            switch targetId {
            case "catalyst", "reactor": return 58 * 3600    // ~58 hours
            case "forma": return 30 * 3600                 // ~30 hours
            case "exilus_wf", "exilus_wp": return 96 * 3600 // ~4 days
            case "mutagen_mass": return 18 * 3600          // ~18 hours
            default: return 48 * 3600
            }
        }
        return intervals.reduce(0, +) / Double(intervals.count)
    }
    
    public func elapsedSeconds(from now: Date = Date()) -> TimeInterval {
        guard let last = lastSeenDate else {
            // Default to mean * 0.6 if never recorded
            return meanInterval * 0.6
        }
        return max(0, now.timeIntervalSince(last))
    }
    
    // Fitted cumulative probability via Poisson arrival process: 1 - e^(-t / mean)
    public func fittedProbability(from now: Date = Date()) -> Int {
        let elapsed = elapsedSeconds(from: now)
        let mean = meanInterval
        guard mean > 0 else { return 50 }
        let prob = 1.0 - exp(-elapsed / mean)
        return min(95, max(10, Int(prob * 100)))
    }
    
    public func formattedLastSeen(from now: Date = Date()) -> String {
        guard let last = lastSeenDate else { return "未录得" }
        let hours = Int(now.timeIntervalSince(last) / 3600)
        if hours < 1 { return "刚刚" }
        if hours < 24 { return "\(hours)小时前" }
        let days = hours / 24
        return "\(days)天前"
    }
    
    public func formattedMeanInterval() -> String {
        let hours = Int(meanInterval / 3600)
        if hours < 24 { return "\(hours)小时" }
        return String(format: "%.1f天", Double(hours) / 24.0)
    }
}
