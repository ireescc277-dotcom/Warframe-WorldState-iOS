import Foundation
import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class WorldStateViewModel: ObservableObject {
    /// 后台刷新任务在没有 SwiftUI 视图的情况下也要拿到同一个实例，
    /// 所以这里只能有一个。App 里用 `@StateObject` 挂的就是它。
    public static let shared = WorldStateViewModel()

    // MARK: - Published Properties
    @Published public var worldState: WorldState?
    @Published public var isLoading: Bool = false
    @Published public var isLive: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var lastUpdated: Date = Date()
    @Published public var currentTime: Date = Date()

    /// 仲裁排程。启动时先用缓存或包里那份，刷新时再问 VPS。
    @Published public private(set) var schedule: ArbitrationSchedule?
    
    // Filters & Search
    @Published public var searchQuery: String = ""
    @Published public var onlyStarred: Bool = false
    @Published public var selectedEra: String? = nil // Nil = All, or "VoidT1", "VoidT2", etc.
    @Published public var isSteelPathOnly: Bool = false
    @Published public var selectedMissionCategory: MissionCategory = .fissures
    @Published public var selectedHubCategory: HubCategory = .goals
    
    // Invasions Filter
    public enum InvasionFilter: String, CaseIterable, Identifiable {
        case all = "全部奖励"
        case potato = "土豆"
        case forma = "Forma"
        case exilus = "特殊槽"
        case parts = "武器部件"
        case resources = "道场材料"
        public var id: String { rawValue }
    }
    @Published public var selectedInvasionFilter: InvasionFilter = .all
    @Published public var hideCompletedInvasions: Bool = true
    
    // Watchlist & Notifications
    @Published public var watchItems: [String: WatchItem] = [:]
    /// 开打提醒总开关。权限是另一件事：开关打开时才去问系统要。
    @Published public var notificationsEnabled: Bool = false
    @Published public var notificationPermission: NotificationPermission = .notDetermined
    /// 当前排出去的计划条数，界面上要给个数，否则用户不知道有没有生效。
    @Published public var pendingAlertCount: Int = 0

    // Exhaustive watch tree
    public let watchTree: WatchTreeIndex
    @Published public var watchSelection: WatchSelection
    @Published public var expandedWatchIDs: Set<String> = []
    @Published public var liveWatchHits: [WatchHit] = []
    
    // Diffs
    @Published public var currentDiffs: [DiffGroup] = []
    @Published public var diffSummaryCount: Int = 0
    
    // MARK: - Private
    private var timerCancellable: AnyCancellable?
    private let dict = DictionaryService.shared
    private let storage = StorageService.shared
    private let service = WorldStateService.shared
    private let notificationService = NotificationService.shared
    /// Last known arbitration. Kept across refreshes so a single failed poll of
    /// the community mirror does not make an active arbitration disappear.
    private var arbitrationInfo: ArbitrationInfo?
    
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
    
    /// `-watchPreset arb` seeds a selection so the screenshot gate can photograph
    /// the watch screen with targets filled in. The reminder row only appears
    /// once something is selected, so without this the gate never sees it.
    private static var seededWatchPaths: [String]? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "-watchPreset"),
              args.index(after: flag) < args.endIndex else { return nil }
        return args[args.index(after: flag)].split(separator: ",").map(String.init)
    }

    public init() {
        let tree = WatchTreeIndex(dictionary: DictionaryService.shared)
        self.watchTree = tree
        self.watchSelection = WatchSelection(paths: StorageService.shared.loadWatchPaths())
        self.expandedWatchIDs = Set(tree.roots.map { $0.id })

        self.watchItems = storage.loadWatchItems()
        self.schedule = ArbitrationScheduleStore.localized()
        self.notificationsEnabled = storage.loadNotificationsEnabled()
        if let seeded = Self.seededWatchPaths {
            // 只进内存，不写 UserDefaults：这是给 CI 截图用的取景参数，
            // 不该改掉用户自己的选择。
            var updated = self.watchSelection
            for path in seeded where tree.node(path) != nil {
                updated.select(path)
            }
            self.watchSelection = updated
        }
        setupTimer()
        checkNotificationStatus()
        loadInitialData()
        // 服务器上的蹲守选择必须等于这台设备勾的那份，否则推的就是别人的偏好。
        WatchSync.shared.syncNow(self.watchSelection.paths)
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
        notificationService.permission { [weak self] permission in
            guard let self else { return }
            self.notificationPermission = permission
            if permission.isAuthorized, self.notificationsEnabled {
                self.rebuildNotifications()
            }
        }
    }

    /// 打开开关时才问权限。第一次进 App 就弹系统框，多数人只会条件反射点拒绝，
    /// 之后再想开就得去设置里翻。
    public func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        storage.saveNotificationsEnabled(enabled)

        guard enabled else {
            notificationService.clearPlanned()
            pendingAlertCount = 0
            return
        }

        if notificationPermission.isAuthorized {
            rebuildNotifications()
        } else {
            notificationService.requestPermission { [weak self] permission in
                guard let self else { return }
                self.notificationPermission = permission
                if permission.isAuthorized {
                    self.rebuildNotifications()
                } else {
                    // 拒了就落回关闭状态，别留一个永远排不出东西的开关。
                    self.notificationsEnabled = false
                    self.storage.saveNotificationsEnabled(false)
                    self.pendingAlertCount = 0
                }
            }
        }
    }

    /// 按当前选择重排「确定性事件」的提醒。刷新、改选择、换到新排程之后都要调。
    public func rebuildNotifications() {
        guard notificationsEnabled, notificationPermission.isAuthorized else {
            pendingAlertCount = 0
            return
        }
        let alerts = NotificationPlan.build(
            selection: watchSelection,
            tree: watchTree,
            schedule: schedule,
            state: worldState,
            starred: watchItems.values.filter(\.isReminderEnabled)
        )
        notificationService.apply(alerts) { [weak self] in
            guard let self else { return }
            self.notificationService.pendingCount { count in
                self.pendingAlertCount = count
            }
        }
    }

    /// 裂隙、入侵、风暴没有排程，刷新到的那一刻才知道，只能立刻发。
    ///
    /// 两条克制：只在 App 退到后台时发（在前台你自己就看见了）；同一条命中
    /// 只报一次，靠 `notifiedHits` 账本去重。
    private func postNewLiveHits() {
        let now = Date()
        var ledger = storage.loadNotifiedHits().filter { $0.value > now.timeIntervalSince1970 }

        let fresh = matchedLiveHits.filter { ledger[$0.id] == nil }
        guard notificationsEnabled, notificationPermission.isAuthorized, !fresh.isEmpty else { return }

        #if canImport(UIKit)
        // .inactive 也算前台：冷启动那一瞬间就是 inactive，那时候不需要提醒。
        guard UIApplication.shared.applicationState == .background else { return }

        // 账本要等真的投递出去之后才记。以前是先记账再判断能不能发，于是前台
        // 刷新一次就把这批命中吃掉了，之后进后台也不会再补——表现就是「从来
        // 没在关注的东西出现时收到过通知」。
        for hit in fresh {
            ledger[hit.id] = (hit.expiry ?? now.addingTimeInterval(24 * 3600)).timeIntervalSince1970
        }
        storage.saveNotifiedHits(ledger)

        // 一次最多三条，先给最快结束的，剩下的回 App 就看见了。
        let ordered = fresh.sorted {
            ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture)
        }
        notificationService.post(ordered)
        #endif
    }
    
    // MARK: - Data Loading & Refresh
    public func loadInitialData() {
        if let initial = service.loadBundledSnapshot() {
            self.worldState = initial
            self.isLive = false
            computeDiff(newWorldState: initial)
            refreshLiveWatchHits()
        }
        
        Task {
            await refreshData()
        }
    }
    
    public func refreshData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let arbitration = WorldStateService.fetchArbitration()
            async let scheduleTask = ArbitrationScheduleStore.fetch()
            let (state, live) = try await service.fetchWorldState()
            self.worldState = state
            self.isLive = live
            self.lastUpdated = Date()
            computeDiff(newWorldState: state)
            if let fresh = await arbitration {
                arbitrationInfo = fresh
            }
            if let fresh = await scheduleTask, fresh.covers(Date()) {
                // 远端可能还没跟上（VPS 上的那份比手里的旧），别降级。
                if schedule == nil || fresh.builtAt >= (schedule?.builtAt ?? 0) {
                    schedule = fresh
                }
            }
            refreshLiveWatchHits()
            WatchSync.shared.syncNow(watchSelection.paths)
        } catch {
            let details = service.lastErrorDetails ?? error.localizedDescription
            self.errorMessage = "刷新失败: \(details)"
            if self.worldState == nil {
                if let fallback = service.loadBundledSnapshot() {
                    self.worldState = fallback
                    self.isLive = false
                    computeDiff(newWorldState: fallback)
                    refreshLiveWatchHits()
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
            refreshLiveWatchHits()
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
        } else {
            watchItems[key] = WatchItem(key: key, label: label, section: section, expiry: expiry)
        }
        storage.saveWatchItems(watchItems)
        rebuildNotifications()
    }

    public func toggleReminder(for key: String) {
        guard var item = watchItems[key] else { return }
        item.isReminderEnabled.toggle()
        watchItems[key] = item
        storage.saveWatchItems(watchItems)
    }
    
    public var sortedWatchItems: [WatchItem] {
        watchItems.values.sorted { a, b in
            let aExp = a.expiry ?? Date.distantFuture
            let bExp = b.expiry ?? Date.distantFuture
            return aExp < bExp
        }
    }
    
    // MARK: - Exhaustive Watch Tree
    public func watchSelectionState(_ id: String) -> WatchSelectionState {
        watchSelection.state(of: id)
    }
    
    public func toggleWatchSelection(_ id: String) {
        var updated = watchSelection
        updated.toggle(id, tree: watchTree)
        watchSelection = updated
        storage.saveWatchPaths(updated.paths)
        WatchSync.shared.schedule(updated.paths)
        rebuildNotifications()
    }

    /// Adds a whole branch in one tap, used by the empty-state presets. Adding
    /// rather than replacing means tapping two presets is additive, which is
    /// what the buttons imply.
    public func addWatchPaths(_ paths: [String]) {
        var updated = watchSelection
        for path in paths where watchTree.node(path) != nil {
            updated.select(path)
        }
        watchSelection = updated
        storage.saveWatchPaths(updated.paths)
        WatchSync.shared.schedule(updated.paths)
        rebuildNotifications()
    }
    
    public func isWatchExpanded(_ id: String) -> Bool {
        expandedWatchIDs.contains(id)
    }
    
    public func toggleWatchExpansion(_ id: String) {
        if expandedWatchIDs.contains(id) {
            expandedWatchIDs.remove(id)
        } else {
            expandedWatchIDs.insert(id)
        }
    }
    
    public func liveHitCount(for id: String) -> Int {
        let prefix = id + "|"
        return liveWatchHits.reduce(0) { partial, hit in
            partial + ((hit.path == id || hit.path.hasPrefix(prefix)) ? 1 : 0)
        }
    }
    
    public var matchedLiveHits: [WatchHit] {
        liveWatchHits.filter { watchSelection.isCovered($0.path) }
    }
    
    public func nextOccurrence(for id: String) -> Date? {
        guard let state = worldState else { return nil }
        return watchTree.nextOccurrence(for: id, in: state, schedule: schedule)
    }

    /// 盘面一变就把三件派生的事一次做完：界面上的命中列表、要提前排的提醒、
    /// 以及「刚才在后台时新冒出来的」事件通知。分开写容易出现某条路径漏掉一步。
    private func refreshLiveWatchHits() {
        guard let state = worldState else {
            liveWatchHits = []
            return
        }
        var hits = watchTree.liveHits(in: state)
        // 排程优先。第三方镜像现在只会返回 SolNode000 占位，那句 if 已经是兜底了。
        if let hit = watchTree.arbitrationHit(schedule: schedule)
            ?? watchTree.arbitrationHit(arbitrationInfo) {
            hits.append(hit)
        }
        liveWatchHits = hits

        rebuildNotifications()
        postNewLiveHits()
    }

    // MARK: - 仲裁

    /// 一场仲裁在界面上需要的东西。`planet` 和 `mode` 来自树的路径，
    /// `nodeName` 才是玩家认得的节点名。
    public struct ArbitrationSlotView {
        public let nodeID: String
        public let nodeName: String
        public let planet: String
        public let mode: String
        public let start: Date
        public let end: Date
    }

    public var arbitrationCurrent: ArbitrationSlotView? {
        guard let schedule, schedule.covers(currentTime),
              let slot = schedule.current(at: currentTime) else { return nil }
        return arbitrationView(for: slot.node, start: slot.start, end: slot.end)
    }

    public var arbitrationNext: ArbitrationSlotView? {
        guard let schedule, schedule.covers(currentTime),
              let slot = schedule.next(after: currentTime) else { return nil }
        return arbitrationView(
            for: slot.node,
            start: slot.start,
            end: slot.start.addingTimeInterval(TimeInterval(schedule.slot))
        )
    }

    private func arbitrationView(for nodeID: String, start: Date, end: Date) -> ArbitrationSlotView? {
        guard let path = watchTree.arbitrationPath(for: nodeID) else { return nil }
        let parts = path.split(separator: "|")
        let modeKey = parts.count > 1 ? String(parts[1]) : ""
        return ArbitrationSlotView(
            nodeID: nodeID,
            nodeName: dict.nodeShortName(nodeID),
            planet: parts.count > 2 ? String(parts[2]) : "",
            mode: dict.missionType(modeKey),
            start: start,
            end: end
        )
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
            if hideCompletedInvasions && inv.Completed { return false }
            
            let att = inv.AttackerReward
            let def = inv.DefenderReward
            
            switch selectedInvasionFilter {
            case .all:
                break
            case .potato:
                let hasPotato = (att?.containsKeyword("Catalyst") ?? false) ||
                                (att?.containsKeyword("Reactor") ?? false) ||
                                (att?.containsKeyword("催化剂") ?? false) ||
                                (att?.containsKeyword("反应堆") ?? false) ||
                                (def?.containsKeyword("Catalyst") ?? false) ||
                                (def?.containsKeyword("Reactor") ?? false) ||
                                (def?.containsKeyword("催化剂") ?? false) ||
                                (def?.containsKeyword("反应堆") ?? false)
                if !hasPotato { return false }
            case .forma:
                let hasForma = (att?.containsKeyword("Forma") ?? false) ||
                               (def?.containsKeyword("Forma") ?? false)
                if !hasForma { return false }
            case .exilus:
                let hasExilus = (att?.containsKeyword("Exilus") ?? false) ||
                                (def?.containsKeyword("Exilus") ?? false)
                if !hasExilus { return false }
            case .parts:
                let hasParts = (att?.containsKeyword("Wraith") ?? false) ||
                               (att?.containsKeyword("Vandal") ?? false) ||
                               (def?.containsKeyword("Wraith") ?? false) ||
                               (def?.containsKeyword("Vandal") ?? false)
                if !hasParts { return false }
            case .resources:
                let hasRes = (att?.containsKeyword("Mutagen") ?? false) ||
                             (att?.containsKeyword("Fieldron") ?? false) ||
                             (att?.containsKeyword("Detonite") ?? false) ||
                             (def?.containsKeyword("Mutagen") ?? false) ||
                             (def?.containsKeyword("Fieldron") ?? false) ||
                             (def?.containsKeyword("Detonite") ?? false)
                if !hasRes { return false }
            }
            
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
