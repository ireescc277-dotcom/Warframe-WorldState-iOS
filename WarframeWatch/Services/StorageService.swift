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
}
