import Foundation
import Combine
import SwiftUI

@MainActor
public final class WorldStateViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var worldState: WorldState?
    @Published public var isLoading: Bool = false
    @Published public var isLive: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var lastUpdated: Date = Date()
    @Published public var currentTime: Date = Date()
    
    // Filters & Search
    @Published public var searchQuery: String = ""
    @Published public var onlyStarred: Bool = false
    @Published public var selectedEra: String? = nil // Nil = All, or "VoidT1", "VoidT2", etc.
    @Published public var isSteelPathOnly: Bool = false
    @Published public var selectedMissionCategory: MissionCategory = .fissures
    @Published public var selectedHubCategory: HubCategory = .goals
    
    // Watchlist & Notifications
    @Published public var watchItems: [String: WatchItem] = [:]
    @Published public var subscribedCatalogIds: Set<String> = []
    @Published public var isNotificationAuthorized: Bool = false
    
    // Diffs
    @Published public var currentDiffs: [DiffGroup] = []
    @Published public var diffSummaryCount: Int = 0
    
    // MARK: - Private
    private var timerCancellable: AnyCancellable?
    private let dict = DictionaryService.shared
    private let storage = StorageService.shared
    private let service = WorldStateService.shared
    private let notificationService = NotificationService.shared
    
    public enum MissionCategory: String, CaseIterable, Identifiable {
        case fissures = "虚空裂隙"
        case alerts = "限时警报"
        case invasions = "入侵事件"
        case storms = "虚空风暴"
        public var id: String { rawValue }
    }
    
    public enum HubCategory: String, CaseIterable, Identifiable {
        case goals = "社区目标"
        case nightwave = "午夜电波"
        case syndicates = "集团任务"
        case news = "官方公告"
        case flashSales = "商城促销"
        public var id: String { rawValue }
    }
    
    public init() {
        self.watchItems = storage.loadWatchItems()
        self.subscribedCatalogIds = storage.loadCatalogSubscriptions()
        setupTimer()
        checkNotificationStatus()
        loadInitialData()
    }
    
    // MARK: - Timer for Countdowns
    private func setupTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.currentTime = now
            }
    }
    
    private func checkNotificationStatus() {
        notificationService.checkPermission { [weak self] authorized in
            self?.isNotificationAuthorized = authorized
        }
    }
    
    public func requestNotificationPermission() {
        notificationService.requestPermission { [weak self] granted in
            self?.isNotificationAuthorized = granted
        }
    }
    
    // MARK: - Data Loading & Refresh
    public func loadInitialData() {
        if let initial = service.loadBundledSnapshot() {
            self.worldState = initial
            self.isLive = false
            computeDiff(newWorldState: initial)
        }
        
        Task {
            await refreshData()
        }
    }
    
    public func refreshData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let (state, live) = try await service.fetchWorldState()
            self.worldState = state
            self.isLive = live
            self.lastUpdated = Date()
            computeDiff(newWorldState: state)
        } catch {
            let details = service.lastErrorDetails ?? error.localizedDescription
            self.errorMessage = "刷新失败: \(details)"
            if self.worldState == nil {
                if let fallback = service.loadBundledSnapshot() {
                    self.worldState = fallback
                    self.isLive = false
                    computeDiff(newWorldState: fallback)
                }
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Debug & Custom API Host
    public var activeApiUrlString: String {
        service.activeApiUrl.absoluteString
    }
    
    public func updateCustomApiUrl(_ urlString: String) {
        service.setCustomApiUrl(urlString)
        Task {
            await refreshData()
        }
    }
    
    public func resetToDefaultApiUrl() {
        service.setCustomApiUrl(nil)
        Task {
            await refreshData()
        }
    }
    
    public func loadBundledSnapshotDirectly() {
        if let initial = service.loadBundledSnapshot() {
            self.worldState = initial
            self.isLive = false
            self.errorMessage = nil
            computeDiff(newWorldState: initial)
        }
    }
    
    public var diagnosticInfo: (duration: TimeInterval, bytes: Int, status: Int, error: String?) {
        (service.lastFetchDuration, service.lastResponseBytes, service.lastHttpStatus, service.lastErrorDetails)
    }
    
    // MARK: - Watchlist Management
    public func isStarred(key: String) -> Bool {
        watchItems[key] != nil
    }
    
    public func toggleWatchItem(key: String, label: String, section: String, expiry: Date?) {
        if watchItems[key] != nil {
            watchItems.removeValue(forKey: key)
            notificationService.cancelReminder(for: key)
        } else {
            let item = WatchItem(key: key, label: label, section: section, expiry: expiry)
            watchItems[key] = item
            if item.isReminderEnabled {
                notificationService.scheduleReminder(for: item)
            }
        }
        storage.saveWatchItems(watchItems)
    }
    
    public func toggleReminder(for key: String) {
        guard var item = watchItems[key] else { return }
        item.isReminderEnabled.toggle()
        watchItems[key] = item
        
        if item.isReminderEnabled {
            notificationService.scheduleReminder(for: item)
        } else {
            notificationService.cancelReminder(for: key)
        }
        storage.saveWatchItems(watchItems)
    }
    
    public var sortedWatchItems: [WatchItem] {
        watchItems.values.sorted { a, b in
            let aExp = a.expiry ?? Date.distantFuture
            let bExp = b.expiry ?? Date.distantFuture
            return aExp < bExp
        }
    }
    
    // MARK: - Watch Target Catalog
    public func isCatalogSubscribed(_ id: String) -> Bool {
        subscribedCatalogIds.contains(id)
    }
    
    public func toggleCatalogSubscription(_ id: String) {
        if subscribedCatalogIds.contains(id) {
            subscribedCatalogIds.remove(id)
        } else {
            subscribedCatalogIds.insert(id)
        }
        storage.saveCatalogSubscriptions(subscribedCatalogIds)
    }
    
    public var evaluatedCatalogItems: [EvaluatedWatchItem] {
        guard let ws = worldState else { return [] }
        let items = WatchCatalogDatabase.shared.items.map { item -> EvaluatedWatchItem in
            let state = item.evaluate(ws)
            return EvaluatedWatchItem(item: item, state: state, isSubscribed: subscribedCatalogIds.contains(item.id))
        }
        
        return items.sorted { a, b in
            if a.state.sortOrder != b.state.sortOrder {
                return a.state.sortOrder < b.state.sortOrder
            }
            if case let .active(_, _, remA) = a.state, case let .active(_, _, remB) = b.state {
                if remA > 0 && remB > 0 { return remA < remB }
                if remA > 0 { return true }
                return false
            }
            if case let .deterministic(_, remA, _) = a.state, case let .deterministic(_, remB, _) = b.state {
                return remA < remB
            }
            if case let .probabilistic(_, _, pctA, _) = a.state, case let .probabilistic(_, _, pctB, _) = b.state {
                return pctA > pctB
            }
            return false
        }
    }
    
    // MARK: - Fingerprint & Snapshot Diff
    private func computeDiff(newWorldState: WorldState) {
        let currentFp = generateFingerprint(for: newWorldState)
        var history = storage.loadHistoryFingerprints()
        
        if let previous = history.last {
            let diffs = compareFingerprints(previous: previous, current: currentFp)
            self.currentDiffs = diffs
            self.diffSummaryCount = diffs.reduce(0) { $0 + $1.totalChanges }
        } else {
            self.currentDiffs = []
            self.diffSummaryCount = 0
        }
        
        history.append(currentFp)
        storage.saveHistoryFingerprints(history)
    }
    
    private func generateFingerprint(for state: WorldState) -> WorldStateFingerprint {
        var sets: [String: [String: String]] = [:]
        var metrics: [String: [String: String]] = [:]
        
        func add(_ group: String, _ key: String, _ label: String, metric: String? = nil) {
            if sets[group] == nil { sets[group] = [:] }
            sets[group]?[key] = label
            if let metric = metric {
                if metrics[group] == nil { metrics[group] = [:] }
                metrics[group]?[key] = metric
            }
        }
        
        // Alerts
        state.Alerts?.forEach { a in
            let node = a.MissionInfo?.location ?? ""
            let mType = a.MissionInfo?.missionType ?? ""
            let label = "\(dict.missionType(mType)) · \(dict.nodeName(node))"
            add("限时警报", "\(node)_\(mType)", label)
        }
        
        // Invasions
        state.Invasions?.forEach { inv in
            let label = dict.nodeName(inv.Node)
            let metric = "\(abs(inv.Count))/\(inv.targetGoal)"
            add("入侵事件", inv.Node, label, metric: metric)
        }
        
        // Active Missions (Fissures)
        state.ActiveMissions?.forEach { f in
            let label = "\(dict.tierName(f.Modifier)) · \(dict.nodeName(f.Node))"
            let metric = f.isSteelPath ? "钢铁之路" : "普通"
            add("虚空裂隙", "\(f.Node)_\(f.MissionType)_\(f.Modifier)", label, metric: metric)
        }
        
        // Void Storms
        state.VoidStorms?.forEach { s in
            let label = dict.nodeName(s.Node)
            add("虚空风暴", s.Node, label, metric: s.ActiveMissionTier)
        }
        
        // Daily Deals
        state.DailyDeals?.forEach { d in
            let label = dict.itemName(d.StoreItem)
            let metric = "\(d.AmountSold)/\(d.AmountTotal) (\(d.SalePrice)P)"
            add("每日特惠", d.StoreItem, label, metric: metric)
        }
        
        // Sortie
        state.Sorties?.forEach { s in
            let label = dict.bossName(s.Boss)
            add("每日突击", s.Boss, label)
        }
        
        return WorldStateFingerprint(timestamp: Date(), sets: sets, metrics: metrics)
    }
    
    private func compareFingerprints(previous: WorldStateFingerprint, current: WorldStateFingerprint) -> [DiffGroup] {
        var result: [DiffGroup] = []
        let allGroups = Set(previous.sets.keys).union(current.sets.keys)
        
        for group in allGroups.sorted() {
            let prevSet = previous.sets[group] ?? [:]
            let currSet = current.sets[group] ?? [:]
            let prevMetrics = previous.metrics[group] ?? [:]
            let currMetrics = current.metrics[group] ?? [:]
            
            var added: [String] = []
            var removed: [String] = []
            var changed: [MetricChange] = []
            
            for (key, label) in currSet {
                if prevSet[key] == nil {
                    added.append(label)
                } else if let pVal = prevMetrics[key], let cVal = currMetrics[key], pVal != cVal {
                    changed.append(MetricChange(label: label, fromValue: pVal, toValue: cVal))
                }
            }
            
            for (key, label) in prevSet where currSet[key] == nil {
                removed.append(label)
            }
            
            if !added.isEmpty || !removed.isEmpty || !changed.isEmpty {
                result.append(DiffGroup(groupName: group, added: added, removed: removed, changed: changed))
            }
        }
        
        return result
    }
    
    // MARK: - Filtered Collections
    
    public var filteredAlerts: [Alert] {
        guard let list = worldState?.Alerts else { return [] }
        return list.filter { alert in
            let location = dict.nodeName(alert.MissionInfo?.location)
            let mType = dict.missionType(alert.MissionInfo?.missionType)
            let key = "alerts|\(location) · \(mType)"
            
            if onlyStarred && !isStarred(key: key) { return false }
            if searchQuery.isEmpty { return true }
            return location.localizedCaseInsensitiveContains(searchQuery) ||
                   mType.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    public var filteredFissures: [ActiveMission] {
        guard let list = worldState?.ActiveMissions else { return [] }
        return list.filter { fissure in
            if let era = selectedEra, fissure.Modifier != era {
                return false
            }
            if isSteelPathOnly && !fissure.isSteelPath {
                return false
            }
            let nodeName = dict.nodeName(fissure.Node)
            let mType = dict.missionType(fissure.MissionType)
            let key = "fissures|\(fissure.id)"
            
            if onlyStarred && !isStarred(key: key) { return false }
            if searchQuery.isEmpty { return true }
            return nodeName.localizedCaseInsensitiveContains(searchQuery) ||
                   mType.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    public var filteredInvasions: [Invasion] {
        guard let list = worldState?.Invasions else { return [] }
        return list.filter { inv in
            let nodeName = dict.nodeName(inv.Node)
            let key = "invasions|\(inv.Node)"
            
            if onlyStarred && !isStarred(key: key) { return false }
            if searchQuery.isEmpty { return true }
            return nodeName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    public var filteredVoidStorms: [VoidStorm] {
        guard let list = worldState?.VoidStorms else { return [] }
        return list.filter { storm in
            let nodeName = dict.nodeName(storm.Node)
            let key = "storms|\(storm.Node)"
            
            if onlyStarred && !isStarred(key: key) { return false }
            if searchQuery.isEmpty { return true }
            return nodeName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}
