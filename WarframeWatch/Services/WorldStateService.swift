import Foundation

public final class WorldStateService {
    public static let shared = WorldStateService()
    
    public let defaultApiUrl = URL(string: "https://api.warframe.com/cdn/worldState.php")!
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
    
    public func fetchWorldState(customUrl: URL? = nil) async throws -> (WorldState, Bool) {
        let startTime = Date()
        let targetUrl = customUrl ?? activeApiUrl
        var request = URLRequest(url: targetUrl)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 12.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
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
            let duration = Date().timeIntervalSince(startTime)
            self.lastFetchDuration = duration
            self.lastErrorDetails = "网络/解析异常: \(error.localizedDescription)"
            print("❌ fetchWorldState error: \(error)")
            
            // Try loading cached data
            if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
               let state = try? JSONDecoder().decode(WorldState.self, from: cachedData) {
                return (state, false)
            }
            
            // Fallback to bundled snapshot
            if let bundledState = loadBundledSnapshot() {
                return (bundledState, false)
            }
            
            throw error
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
