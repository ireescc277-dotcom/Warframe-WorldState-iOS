import Foundation

/// 把蹲守选择推到 VPS。
///
/// 服务器端监控按 App 里勾的目标推送，否则两边各说各话：你在这里加了「安魂
/// 裂隙」，VPS 还按它自己那份配置推别的东西。
///
/// 只在选择变化后做一次防抖上传，失败静默——同步不上顶多服务器还用旧选择，
/// 不值得弹窗打断。
@MainActor
public final class WatchSync {
    public static let shared = WatchSync()

    private var lastSent: Set<String>?
    private var pending: Task<Void, Never>?

    private init() {}

    /// .../wf/<token>/inventory.json -> .../wf/<token>/watch
    /// 和背包同一个目录、同一个 token，不额外发明一套鉴权。
    private static var endpoint: URL? {
        guard let base = InventoryStore.remote else { return nil }
        return base.deletingLastPathComponent().appendingPathComponent("watch")
    }

    public func schedule(_ paths: Set<String>) {
        guard let endpoint = Self.endpoint else { return }
        guard paths != lastSent else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            // 连着勾好几项时不要每次都发一轮。
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            if await Self.upload(paths, to: endpoint) {
                self?.lastSent = paths
            }
        }
    }

    private static func upload(_ paths: Set<String>, to url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["paths": paths.sorted()]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
