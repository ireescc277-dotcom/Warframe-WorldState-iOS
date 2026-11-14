import Foundation

public final class WorldStateService {
    public static let shared = WorldStateService()
    
    public let defaultApiUrl = URL(string: "https://api.warframe.com/cdn/worldState.php")!
    /// Stays on the public host even when a custom worldState mirror is set,
    /// because a worldState mirror has no reason to proxy arbitration.
    public let arbitrationUrl = URL(string: "https://api.warframestat.us/pc/arbitration?language=en")!
    private let cacheKey = "wf_ws_cached_response"
    public let customUrlKey = "wf_custom_api_url"
    
    public private(set) var lastFetchDuration: TimeInterval = 0
    public private(set) var lastResponseBytes: Int = 0
    public private(set) var lastErrorDetails: String? = nil
    public private(set) var lastHttpStatus: Int = 0
    
    private init() {}
    
    public var activeApiUrl: URL {
        if let customStr = UserDefaults.standard.string(forKey: customUrlKey),
           let url = URL(string: customStr.trimmingCharacters(in: .whitespacesAndNewlines)),
           !customStr.isEmpty {
            return url
        }
        return defaultApiUrl
    }
    
    public func setCustomApiUrl(_ urlString: String?) {
        if let str = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            UserDefaults.standard.set(str, forKey: customUrlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customUrlKey)
        }
    }
    
    private static var vpsFallbackUrl: URL? {
        guard let remote = InventoryStore.remote else { return nil }
        return remote.deletingLastPathComponent().appendingPathComponent("worldstate.json")
    }

    public func fetchWorldState(customUrl: URL? = nil) async throws -> (WorldState, Bool) {
        let primaryUrl = customUrl ?? activeApiUrl
        var candidates: [URL] = [primaryUrl]
        if customUrl == nil, let mirror = Self.vpsFallbackUrl, mirror != primaryUrl {
            candidates.append(mirror)
        }

        var lastError: Error = URLError(.badServerResponse)
        for targetUrl in candidates {
            let startTime = Date()
            var request = URLRequest(url: targetUrl)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 15.0
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let duration = Date().timeIntervalSince(startTime)
                self.lastFetchDuration = duration
                self.lastResponseBytes = data.count

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                self.lastHttpStatus = httpResponse.statusCode

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let decoder = JSONDecoder()
                let state = try decoder.decode(WorldState.self, from: data)

                UserDefaults.standard.set(data, forKey: cacheKey)
                self.lastErrorDetails = nil
                return (state, true)
            } catch {
                self.lastFetchDuration = Date().timeIntervalSince(startTime)
                lastError = error
            }
        }

        self.lastErrorDetails = "网络/解析异常: \(lastError.localizedDescription)"
        print("❌ fetchWorldState error: \(lastError)")

        // Try loading cached data
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let state = try? JSONDecoder().decode(WorldState.self, from: cachedData) {
            return (state, false)
        }

        // Fallback to bundled snapshot
        if let bundledState = loadBundledSnapshot() {
            return (bundledState, false)
        }

        throw lastError
    }
    
    /// Arbitration is absent from DE's worldState feed, so it is read from the
    /// community mirror. Returns `nil` for every failure mode — offline, a bad
    /// payload, or the placeholder stub the feed serves when nothing is running.
    /// Callers keep whatever they had before instead of blanking the UI.
    ///
    /// Static and URL-parameterised on purpose: the caller runs it concurrently
    /// with the worldState fetch, and only a `URL` needs to cross that boundary.
    public static func fetchArbitration(url: URL = WorldStateService.shared.arbitrationUrl) async -> ArbitrationInfo? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 8.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            let info = try JSONDecoder().decode(ArbitrationInfo.self, from: data)
            return info.isPlaceholder ? nil : info
        } catch {
            return nil
        }
    }

    public func loadBundledSnapshot() -> WorldState? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "DefaultSnapshot", withExtension: "json"),
            Bundle.main.url(forResource: "DefaultSnapshot", withExtension: "json", subdirectory: "Resources"),
            Bundle.main.bundleURL.appendingPathComponent("DefaultSnapshot.json"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/DefaultSnapshot.json")
        ]
        
        for candidate in candidates {
            guard let url = candidate, FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let state = try JSONDecoder().decode(WorldState.self, from: data)
                print("✅ Successfully loaded bundled snapshot from \(url.lastPathComponent) (\(data.count) bytes)")
                return state
            } catch {
                print("❌ Failed decoding bundled snapshot from \(url.path): \(error)")
                self.lastErrorDetails = "内置快照解析失败: \(error)"
            }
        }
        
        print("❌ DefaultSnapshot.json resource not found in any candidate path!")
        return nil
    }
}
