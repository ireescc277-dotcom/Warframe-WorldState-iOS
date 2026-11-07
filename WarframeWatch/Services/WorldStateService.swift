import Foundation

public final class WorldStateService {
    public static let shared = WorldStateService()
    
    public let defaultApiUrl = URL(string: "https://api.warframe.com/cdn/worldState.php")!
    private let cacheKey = "wf_ws_cached_response"
    
    private init() {}
    
    public func fetchWorldState(customUrl: URL? = nil) async throws -> (WorldState, Bool) {
        let url = customUrl ?? defaultApiUrl
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let state = try decoder.decode(WorldState.self, from: data)
            
            // Cache on disk
            UserDefaults.standard.set(data, forKey: cacheKey)
            
            return (state, true) // True = isLive
        } catch {
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
        if let url = Bundle.main.url(forResource: "DefaultSnapshot", withExtension: "json") ??
                     Bundle(for: WorldStateService.self).url(forResource: "DefaultSnapshot", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let state = try? JSONDecoder().decode(WorldState.self, from: data) {
            return state
        }
        return nil
    }
}
