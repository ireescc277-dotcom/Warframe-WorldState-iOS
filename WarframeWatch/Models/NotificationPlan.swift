import Foundation

/// 一条排好时间的本地通知。
///
/// 只放数据，不碰 UserNotifications：`NotificationService` 负责把 fireAt 变成
/// `UNTimeIntervalNotificationTrigger`，这里只管「几点、说什么」。分成两层是
/// 因为 CI 的测试跑的是命令行 swiftc，编不进 UIKit 那一套，但排程逻辑恰恰是
/// 最该被断言的部分——预算、去重、提前量都在这里。
public struct PlannedAlert: Identifiable, Equatable {
    public let id: String
    public let fireAt: Date
    public let title: String
    public let body: String
    public let family: String

    public init(id: String, fireAt: Date, title: String, body: String, family: String) {
        self.id = id
        self.fireAt = fireAt
        self.title = title
        self.body = body
        self.family = family
    }
}

/// 把「选了哪些目标」翻译成「接下来该在几点提醒」。
///
/// 只有确定性的事件能提前排：仲裁有 browse.wf 的轮换表，周期与重置靠
/// worldState 里的 expiry 反推，星标的社区目标自带结束时间。裂隙 / 入侵 /
/// 风暴什么时候冒出来是没有排程的，排不了未来，只能在刷新到的那一刻立刻发——
/// 那部分在 `WorldStateViewModel.postNewLiveHits()` 里。
public enum NotificationPlan {
    /// 仲裁提前 5 分钟：够开机、够换配置，又不至于早到忘了。
    public static let arbitrationLead: TimeInterval = 5 * 60
    /// 周期默认也提前 5 分钟。
    public static let cycleLead: TimeInterval = 5 * 60
    /// 社区目标是「还差多少分打完」，提前半小时够上去补一把。
    public static let goalLead: TimeInterval = 30 * 60

    /// iOS 一个 App 最多留 64 条待发通知。留 40 条给计划，剩下的给事件提醒，
    /// 免得排满之后裂隙那条挤不进去。
    public static let defaultLimit = 40

    /// 每个目标最多排几场。仲裁一小时内换一场、排到的节点三十天里也就出现
    /// 几次，两场足够覆盖「今晚这一轮」，又不至于把名额全吃在同一个节点上。
    public static let occurrencesPerTarget = 2

    /// 奥布山谷暖温期整个周期才 6 分 40 秒，提前 5 分钟等于刚结束就提醒下一
    /// 次，没有意义；这一类到点直接响。
    private static func lead(for path: String) -> TimeInterval {
        path == "cycle|vallis|warm" ? 0 : cycleLead
    }

    public static func build(
        selection: WatchSelection,
        tree: WatchTreeIndex,
        schedule: ArbitrationSchedule?,
        state: WorldState?,
        starred: [WatchItem] = [],
        now: Date = Date(),
        limit: Int = defaultLimit
    ) -> [PlannedAlert] {
        guard limit > 0 else { return [] }

        var alerts: [PlannedAlert] = []

        for leaf in tree.coveredLeaves(selection) {
            if leaf.id.hasPrefix("arb|") {
                alerts.append(contentsOf: arbitrationAlerts(
                    for: leaf, tree: tree, schedule: schedule, now: now
                ))
            } else if leaf.id.hasPrefix("cycle|") {
                if let alert = cycleAlert(for: leaf, tree: tree, schedule: schedule, state: state, now: now) {
                    alerts.append(alert)
                }
            }
        }

        for item in starred {
            if let alert = goalAlert(for: item, now: now) {
                alerts.append(alert)
            }
        }

        // 同一时刻按 id 排，保证同样的输入每次排出同样的顺序——测试要能复现。
        let sorted = alerts.sorted { lhs, rhs in
            lhs.fireAt == rhs.fireAt ? lhs.id < rhs.id : lhs.fireAt < rhs.fireAt
        }
        return Array(sorted.prefix(limit))
    }

    private static func goalAlert(for item: WatchItem, now: Date) -> PlannedAlert? {
        guard let expiry = item.expiry else { return nil }
        let fireAt = expiry.addingTimeInterval(-goalLead)
        guard fireAt > now else { return nil }
        return PlannedAlert(
            id: "star.\(item.key).\(Int(expiry.timeIntervalSince1970))",
            fireAt: fireAt,
            title: item.label,
            body: "\(item.section) · \(Int(goalLead / 60)) 分钟后结束",
            family: "关注"
        )
    }

    private static func arbitrationAlerts(
        for leaf: WatchNode,
        tree: WatchTreeIndex,
        schedule: ArbitrationSchedule?,
        now: Date
    ) -> [PlannedAlert] {
        guard let schedule else { return [] }
        let parts = leaf.id.split(separator: "|")
        guard parts.count >= 4, let nodeID = parts.last.map(String.init) else { return [] }
        let modeKey = String(parts[1])
        let planet = String(parts[2])
        let mode = tree.node("arb|\(modeKey)")?.title ?? modeKey

        return schedule.upcomingDates(forNode: nodeID, after: now, limit: occurrencesPerTarget)
            .compactMap { start in
                let fireAt = start.addingTimeInterval(-arbitrationLead)
                guard fireAt > now else { return nil }
                return PlannedAlert(
                    id: "arb.\(nodeID).\(Int(start.timeIntervalSince1970))",
                    fireAt: fireAt,
                    title: "仲裁 · \(leaf.title)",
                    body: "\(planet) · \(mode)，\(Int(arbitrationLead / 60)) 分钟后开始",
                    family: "仲裁"
                )
            }
    }

    private static func cycleAlert(
        for leaf: WatchNode,
        tree: WatchTreeIndex,
        schedule: ArbitrationSchedule?,
        state: WorldState?,
        now: Date
    ) -> PlannedAlert? {
        guard let state,
              let date = tree.nextOccurrence(for: leaf.id, in: state, schedule: schedule, now: now)
        else { return nil }

        let lead = lead(for: leaf.id)
        let fireAt = date.addingTimeInterval(-lead)
        guard fireAt > now else { return nil }

        let parent = tree.parent(of: leaf.id).flatMap { tree.node($0)?.title } ?? "周期"
        let when = lead > 0 ? "\(Int(lead / 60)) 分钟后" : "现在开始"
        return PlannedAlert(
            id: "cyc.\(leaf.id).\(Int(date.timeIntervalSince1970))",
            fireAt: fireAt,
            title: leaf.title,
            body: "\(parent) · \(when)",
            family: "周期"
        )
    }
}
