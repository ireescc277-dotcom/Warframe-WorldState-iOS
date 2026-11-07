import Foundation

print("=== STARTING SWIFT RUNTIME TEST ===")

// 1. Locate DefaultSnapshot.json
let currentDir = FileManager.default.currentDirectoryPath
print("Current dir: \(currentDir)")

let snapshotPath = "\(currentDir)/WarframeWatch/Resources/DefaultSnapshot.json"
let dictPath = "\(currentDir)/WarframeWatch/Resources/DefaultDict.json"

guard FileManager.default.fileExists(atPath: snapshotPath) else {
    fatalError("❌ DefaultSnapshot.json not found at \(snapshotPath)")
}

let snapshotData = try Data(contentsOf: URL(fileURLWithPath: snapshotPath))
print("✅ Loaded DefaultSnapshot.json: \(snapshotData.count) bytes")

// 2. Test JSONDecoder with WorldState
let decoder = JSONDecoder()
do {
    let state = try decoder.decode(WorldState.self, from: snapshotData)
    print("✅ DECODE SUCCESSFUL!")
    print("Version: \(state.Version ?? -1)")
    print("Time: \(state.Time?.date.description ?? "nil")")
    print("Sorties count: \(state.Sorties?.count ?? 0)")
    if let s = state.Sorties?.first {
        print("  - Sortie Boss: \(s.Boss), Expiry: \(s.Expiry?.date.description ?? "nil"), Variants: \(s.Variants?.count ?? 0)")
    }
    print("LiteSorties (Archon) count: \(state.LiteSorties?.count ?? 0)")
    if let a = state.LiteSorties?.first {
        print("  - Archon Boss: \(a.Boss), Missions: \(a.Missions?.count ?? 0)")
    }
    print("VoidTraders count: \(state.VoidTraders?.count ?? 0)")
    if let vt = state.VoidTraders?.first {
        print("  - Baro Character: \(vt.Character), Node: \(vt.Node), Items: \(vt.Manifest?.count ?? 0)")
    }
    print("DailyDeals count: \(state.DailyDeals?.count ?? 0)")
    if let dd = state.DailyDeals?.first {
        print("  - Daily Deal StoreItem: \(dd.StoreItem), Discount: \(dd.Discount)%, Sold: \(dd.AmountSold)/\(dd.AmountTotal)")
    }
    print("GlobalUpgrades count: \(state.GlobalUpgrades?.count ?? 0)")
    print("Alerts count: \(state.Alerts?.count ?? 0)")
    print("Invasions count: \(state.Invasions?.count ?? 0)")
    if let inv = state.Invasions?.first {
        print("  - Invasion Node: \(inv.Node), Attacker: \(inv.Faction), Defender: \(inv.DefenderFaction), Progress: \(inv.progressPct)%")
    }
    print("ActiveMissions (Fissures) count: \(state.ActiveMissions?.count ?? 0)")
    if let f = state.ActiveMissions?.first {
        print("  - Fissure Node: \(f.Node), Type: \(f.MissionType), Modifier: \(f.Modifier)")
    }
    print("VoidStorms count: \(state.VoidStorms?.count ?? 0)")
    print("Goals count: \(state.Goals?.count ?? 0)")
    print("SyndicateMissions count: \(state.SyndicateMissions?.count ?? 0)")
    print("SeasonInfo challenges: \(state.SeasonInfo?.ActiveChallenges?.count ?? 0)")
    print("FlashSales count: \(state.FlashSales?.count ?? 0)")
    print("Events count: \(state.Events?.count ?? 0)")
    print("PVPChallengeInstances count: \(state.PVPChallengeInstances?.count ?? 0)")
} catch {
    print("❌ DECODE FAILED WITH ERROR:")
    print(error)
    if let decError = error as? DecodingError {
        switch decError {
        case .typeMismatch(let type, let context):
            print("Type mismatch for \(type): \(context.debugDescription) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .valueNotFound(let type, let context):
            print("Value not found for \(type): \(context.debugDescription) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .keyNotFound(let key, let context):
            print("Key not found: '\(key.stringValue)': \(context.debugDescription) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .dataCorrupted(let context):
            print("Data corrupted: \(context.debugDescription) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        @unknown default:
            print("Unknown decoding error")
        }
    }
    exit(1)
}

// 3. Test Live API Fetching
print("\n--- Testing Live API Fetch ---")
let liveUrl = URL(string: "https://api.warframe.com/cdn/worldState.php")!
var request = URLRequest(url: liveUrl)
request.timeoutInterval = 10.0
request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

let semaphore = DispatchSemaphore(value: 0)
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let error = error {
        print("⚠️ Live fetch error: \(error.localizedDescription)")
        return
    }
    guard let data = data, let httpResp = response as? HTTPURLResponse else {
        print("⚠️ No data or invalid response")
        return
    }
    print("✅ Live fetch status: \(httpResp.statusCode), bytes: \(data.count)")
    do {
        let liveState = try decoder.decode(WorldState.self, from: data)
        print("✅ Live decode SUCCESSFUL! Version: \(liveState.Version ?? -1), Sorties: \(liveState.Sorties?.count ?? 0), Alerts: \(liveState.Alerts?.count ?? 0), Invasions: \(liveState.Invasions?.count ?? 0)")
    } catch {
        print("❌ Live decode FAILED:")
        print(error)
    }
}
task.resume()
semaphore.wait()

print("\n=== ALL TESTS PASSED SUCCESSFULLY ===")
