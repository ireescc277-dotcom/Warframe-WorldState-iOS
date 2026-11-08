import Foundation

#if os(iOS)
import BackgroundTasks

/// 后台刷新：给「裂隙出现了」这类没有排程的事件补一刀。
///
/// iOS 不保证什么时候给时间片，实际频率取决于使用习惯、电量和系统心情，可能
/// 是十几分钟一次，也可能一天只有两三次。所以这里只是「有可能提前知道」，真正
/// 准点的仍然是 `NotificationPlan` 排出去的那批（仲裁、周期、星标目标）。
///
/// 注册前必须先确认 identifier 写进了 Info.plist 的
/// `BGTaskSchedulerPermittedIdentifiers`，否则 `register` 会直接抛异常崩在
/// 启动阶段——为了一条可选的后台刷新把 App 弄得起不来不值得，所以查不到就
/// 静默跳过，功能降级成「只有前台刷新」。
public enum BackgroundRefresh {
    public static let identifier = "com.warframe.watch.refresh"

    private static var isDeclared: Bool {
        let list = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        return list?.contains(identifier) ?? false
    }

    public static var isSupported: Bool { isDeclared }

    public static func register() {
        guard isDeclared else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // 先把下一次排上，任务失败也不会断链。
            schedule()

            let work = Task { @MainActor in
                await WorldStateViewModel.shared.refreshData()
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    public static func schedule() {
        guard isDeclared else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif
