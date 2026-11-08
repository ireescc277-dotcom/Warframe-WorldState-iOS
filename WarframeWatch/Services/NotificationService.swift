import Foundation
import UserNotifications

public enum NotificationPermission: Equatable {
    case notDetermined
    case denied
    case authorized

    public var isAuthorized: Bool { self == .authorized }
}

/// 本地通知。两层：
///
/// - **排程类**：仲裁、周期、重置。这些时间在 App 关掉之后依然成立，所以每次
///   刷新就整批重排一次（先删 `wf.plan.` 前缀的，再按新计划写回去）。关掉 App
///   也照样会响。
/// - **事件类**：裂隙 / 入侵 / 风暴。出现才知道，只能在刷新到的那一刻立刻发，
///   由 `post(_:)` 负责，且调用方要保证 App 不在前台——不然你正看着屏幕，
///   通知还弹出来就是噪音。
public final class NotificationService {
    public static let shared = NotificationService()

    /// 重排时整批删，不逐个比对，省掉一次 pending 列表的差集计算。
    static let plannedPrefix = "wf.plan."
    /// 事件命中用命中 id 当后缀，同一件事重复刷新只覆盖同一条。
    static let hitPrefix = "wf.hit."

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - 权限

    public func permission(_ completion: @escaping (NotificationPermission) -> Void) {
        center.getNotificationSettings { settings in
            let value: NotificationPermission
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                value = .authorized
            case .denied:
                value = .denied
            default:
                value = .notDetermined
            }
            DispatchQueue.main.async { completion(value) }
        }
    }

    public func requestPermission(_ completion: @escaping (NotificationPermission) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            self.permission(completion)
        }
    }

    // MARK: - 排程类

    public func apply(_ alerts: [PlannedAlert], completion: (() -> Void)? = nil) {
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.plannedPrefix) }
            if !stale.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: stale)
            }

            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = .default
                content.threadIdentifier = alert.family

                // 已经过点的排不进去，补 1 秒兜底而不是直接丢，免得刚好卡在边界上。
                let interval = max(1, alert.fireAt.timeIntervalSinceNow)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(
                    identifier: Self.plannedPrefix + alert.id,
                    content: content,
                    trigger: trigger
                )
                self.center.add(request)
            }

            DispatchQueue.main.async { completion?() }
        }
    }

    public func clearPlanned() {
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.plannedPrefix) }
            guard !stale.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    public func pendingCount(_ completion: @escaping (Int) -> Void) {
        center.getPendingNotificationRequests { pending in
            let count = pending.filter { $0.identifier.hasPrefix(Self.plannedPrefix) }.count
            DispatchQueue.main.async { completion(count) }
        }
    }

    // MARK: - 事件类

    /// 立刻发，最多 `limit` 条。同一批里前几条最可能是用户最想知道的，多出来的
    /// 反正回 App 就能看到，不值得一次刷一屏通知。
    public func post(_ hits: [WatchHit], limit: Int = 3) {
        guard !hits.isEmpty else { return }
        for hit in hits.prefix(limit) {
            let content = UNMutableNotificationContent()
            content.title = hit.title
            content.body = "\(hit.family) · \(hit.detail)"
            content.sound = .default
            content.threadIdentifier = hit.family

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.hitPrefix + hit.id,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}
