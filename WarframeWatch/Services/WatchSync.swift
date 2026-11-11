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
    private var lastLevel: String?
    private var pending: Task<Void, Never>?

    private init() {}

    /// .../wf/<token>/inventory.json -> .../wf/<token>/watch
    /// 和背包同一个目录、同一个 token，不额外发明一套鉴权。
    private static var endpoint: URL? {
        guard let base = InventoryStore.remote else { return nil }
        return base.deletingLastPathComponent().appendingPathComponent("watch")
    }

    public func schedule(_ paths: Set<String>, level: String) {
        guard let endpoint = Self.endpoint else { return }
        guard paths != lastSent || level != lastLevel else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            // 连着勾好几项时不要每次都发一轮。
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            if await Self.upload(paths, level: level, to: endpoint) {
                self?.lastSent = paths
                self?.lastLevel = level
            }
        }
    }

    /// 启动和每次刷新都调一次。
    ///
    /// 只在「选择变了」时上传不够：换机、重装、某次上传失败之后，服务器会一直
    /// 按旧的那份推，而 App 里看不到任何异样——表现出来就是「推的都是我没勾的，
    /// 我勾的从来没响过」。这里每次都把当前选择对一遍，服务器一致就只比较不发包。
    public func syncNow(_ paths: Set<String>, level: String) {
        guard let endpoint = Self.endpoint else { return }
        guard paths != lastSent || level != lastLevel else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            if await Self.upload(paths, level: level, to: endpoint) {
                self?.lastSent = paths
                self?.lastLevel = level
                return
            }
            // 失败重试一次，还不行就等下个刷新点。
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            if await Self.upload(paths, level: level, to: endpoint) {
                self?.lastSent = paths
                self?.lastLevel = level
            }
        }
    }

    private static func upload(_ paths: Set<String>, level: String, to url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["paths": paths.sorted(), "alertLevel": level]
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
