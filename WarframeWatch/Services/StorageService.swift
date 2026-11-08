import Foundation

public final class StorageService {
    public static let shared = StorageService()
    
    private let watchItemsKey = "wf_ws_watch_items"
    private let historyKey = "wf_ws_history_fingerprints"
    
    private init() {}
    
    // MARK: - Watch Items
    public func loadWatchItems() -> [String: WatchItem] {
        guard let data = UserDefaults.standard.data(forKey: watchItemsKey),
              let items = try? JSONDecoder().decode([String: WatchItem].self, from: data) else {
            return [:]
        }
        return items
    }
    
    public func saveWatchItems(_ items: [String: WatchItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: watchItemsKey)
        }
    }
    
    // MARK: - History Fingerprints (Diff)
    public func loadHistoryFingerprints() -> [WorldStateFingerprint] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let list = try? JSONDecoder().decode([WorldStateFingerprint].self, from: data) else {
            return []
        }
        return list
    }
    
    public func saveHistoryFingerprints(_ list: [WorldStateFingerprint]) {
        let trimmed = Array(list.suffix(50)) // Keep last 50 snapshots
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    // MARK: - Watch Tree Selection
    private let watchPathsKey = "wf_watch_paths_v1"
    
    public func loadWatchPaths() -> Set<String> {
        guard let list = UserDefaults.standard.stringArray(forKey: watchPathsKey) else {
            return []
        }
        return Set(list)
    }
    
    public func saveWatchPaths(_ paths: Set<String>) {
        UserDefaults.standard.set(Array(paths), forKey: watchPathsKey)
    }
    
    // MARK: - Event History Records
    private let eventHistoryKey = "wf_ws_event_history_v1"
    
    public func loadEventHistory() -> [String: EventHistoryStats] {
        guard let data = UserDefaults.standard.data(forKey: eventHistoryKey),
              let map = try? JSONDecoder().decode([String: EventHistoryStats].self, from: data) else {
            return [:]
        }
        return map
    }
    
    public func saveEventHistory(_ history: [String: EventHistoryStats]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: eventHistoryKey)
        }
    }
    
    public func recordAppearance(for targetId: String, at date: Date = Date()) {
        var map = loadEventHistory()
        var stat = map[targetId] ?? EventHistoryStats(targetId: targetId)
        
        if let last = stat.lastSeenDate {
            let interval = date.timeIntervalSince(last)
            // If at least 30 minutes have elapsed, record as a new interval between appearances
            if interval > 1800 {
                stat.intervals.append(interval)
                if stat.intervals.count > 50 {
                    stat.intervals.removeFirst(stat.intervals.count - 50)
                }
            }
        } else {
            stat.firstSeenDate = date
        }
        
        stat.lastSeenDate = date
        stat.totalSeenCount += 1
        map[targetId] = stat
        saveEventHistory(map)
    }
}
