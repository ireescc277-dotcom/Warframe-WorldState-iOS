import Foundation

// 断言失败是 SIGTRAP 直接终止进程，stdout 接的是管道、默认 4KB 块缓冲，
// 缓冲区里那些 print 会一起丢掉——崩溃前跑到哪一步就再也看不出来了。
setvbuf(stdout, nil, _IONBF, 0)

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

// 4. Test Exhaustive Watch Tree against the bundled snapshot (runs offline too)
print("\n--- Testing Exhaustive Watch Tree ---")

func leaves(of node: WatchNode) -> [WatchNode] {
    node.isLeaf ? [node] : node.children.flatMap { leaves(of: $0) }
}

func nodeCount(in node: WatchNode) -> Int {
    1 + node.children.reduce(0) { $0 + nodeCount(in: $1) }
}

let dictURL = URL(fileURLWithPath: dictPath)
let dictionary = DictionaryService(dictionaryURL: dictURL)
let tree = WatchTreeIndex(dictionary: dictionary)
print("Tree roots: \(tree.roots.map { $0.title }.joined(separator: " / "))")
print("Tree node count: \(tree.nodeCount)")
for root in tree.roots {
    print("  \(root.title): \(nodeCount(in: root)) nodes, \(leaves(of: root).count) leaves")
}
precondition(tree.nodeCount > 2000, "watch tree is suspiciously small")

let probe = "fis|VoidT1|nm|MT_CAPTURE|SolNode1"
precondition(tree.node(probe) != nil, "probe leaf must exist in the tree")
var selection = WatchSelection()
selection.select("fis|VoidT1")
precondition(selection.isCovered(probe), "era selection must cover leaf")

selection.toggle("fis|VoidT1|nm|MT_CAPTURE", tree: tree)
precondition(!selection.isCovered(probe), "unchecking a mode must release that leaf")
precondition(selection.isCovered("fis|VoidT1|sp|MT_CAPTURE|SolNode1"), "sibling branch must stay selected")

selection.toggle("fis", tree: tree)
precondition(selection.isCovered(probe), "root selection must cover everything")

selection.toggle("fis", tree: tree)
precondition(!selection.isCovered(probe), "root unselect must clear")

for root in tree.roots {
    selection.select(root.id)
}
let treeState = try? decoder.decode(WorldState.self, from: snapshotData)
if let treeState = treeState {
    let watchHits = tree.liveHits(in: treeState)
    precondition(watchHits.allSatisfy { selection.isCovered($0.path) }, "selecting every root must cover every live hit")
    print("Live watch hits (snapshot): \(watchHits.count)")
    print("✅ Watch tree built \(tree.nodeCount) nodes and matched \(watchHits.count) live hits")
}

// 5. Structural guards on the tree itself
print("\n--- Testing Watch Tree Shape ---")

let allLeaves = tree.roots.flatMap { leaves(of: $0) }
precondition(
    !allLeaves.contains { $0.id.contains("|CrewBattleNode") },
    "Railjack nodes never host fissures or arbitrations and must not become leaves"
)

let fissureRoot = tree.roots.first { $0.id == "fis" }
let fissureModes = (fissureRoot?.children ?? []).flatMap { $0.children }.flatMap { $0.children }
precondition(fissureModes.count == 6 * 2 * 19, "expected 19 fissure modes across 6 eras x 2 difficulties")
let emptyFissureMode = fissureModes.first { $0.children.isEmpty }
precondition(emptyFissureMode == nil, "fissure branch '\(emptyFissureMode?.title ?? "?")' has no nodes")

let arbRoot = tree.roots.first { $0.id == "arb" }
precondition(arbRoot?.children.count == 12, "arbitration must list all 12 endless mission types")
precondition(
    arbRoot?.children.allSatisfy { !$0.children.isEmpty } ?? false,
    "every arbitration mission type needs at least one node to be watchable"
)

// A live arbitration has to resolve to the exact leaf its selection path uses.
if let modeBranch = arbRoot?.children.first(where: { !$0.children.isEmpty }),
   let planetBranch = modeBranch.children.first(where: { !$0.children.isEmpty }),
   let arbLeaf = planetBranch.children.first,
   let arbNodeID = arbLeaf.id.split(separator: "|").last.map(String.init) {
    let live = ArbitrationInfo(nodeKey: arbNodeID, type: "Defense", expired: false)
    guard let hit = tree.arbitrationHit(live) else {
        fatalError("live arbitration on \(arbNodeID) must produce a hit")
    }
    precondition(hit.path == arbLeaf.id, "arbitration hit must point at its own leaf, got \(hit.path)")

    var arbSelection = WatchSelection()
    arbSelection.select("arb")
    precondition(arbSelection.isCovered(hit.path), "selecting the arbitration root must cover the hit")

    let stub = ArbitrationInfo(nodeKey: "SolNode000", type: "Unknown", expired: true)
    precondition(tree.arbitrationHit(stub) == nil, "the feed's placeholder arbitration must not produce a hit")
    print("✅ Arbitration hit resolves to \(hit.path)")
}

// ---- 仲裁排程：browse.wf 的轮换表是确定性的，App 用它取代已经失效的
//      第三方镜像（那个接口现在永远返回 SolNode000 占位）。
let scheduleJSON = """
{"builtAt":1794146400,"slot":3600,"slots":[
 {"t":1794146400,"n":"SolNode211"},
 {"t":1794150000,"n":"SolNode94"},
 {"t":1794153600,"n":"SolNode230"}
]}
""".data(using: .utf8)!
let schedule = try JSONDecoder().decode(ArbitrationSchedule.self, from: scheduleJSON)
let insideFirst = Date(timeIntervalSince1970: 1794147000)
precondition(schedule.covers(insideFirst))
precondition(schedule.current(at: insideFirst)?.node == "SolNode211",
             "the slot that started at 1794146400 should still be running")
precondition(schedule.next(after: insideFirst)?.node == "SolNode94")
precondition(schedule.nextDate(forNode: "SolNode94", after: insideFirst)
                == Date(timeIntervalSince1970: 1794150000))
precondition(schedule.nextDate(forNode: "SolNode211", after: insideFirst) == nil,
             "each node appears once here; no later date to report")
precondition(!schedule.covers(Date(timeIntervalSince1970: 1794157200)),
             "a schedule that has run out must not be used")
print("✅ ArbitrationSchedule: \(schedule.isEmpty ? "empty" : "3 slots"), "
      + "current=\(schedule.current(at: insideFirst)?.node ?? "-")")

// 树上的仲裁行也要查得到下一次；分组节点取子树里最近的一次。
if let arbRoot = tree.roots.first(where: { $0.id == "arb" }),
   let modeBranch = arbRoot.children.first(where: { !$0.children.isEmpty }),
   let planetBranch = modeBranch.children.first(where: { !$0.children.isEmpty }),
   let arbLeaf = planetBranch.children.first,
   let leafNodeID = arbLeaf.id.split(separator: "|").last.map(String.init) {
    let fixture = """
    {"builtAt":0,"slot":3600,"slots":[{"t":1794146400,"n":"\(leafNodeID)"}]}
    """.data(using: .utf8)!
    let oneSlot = try JSONDecoder().decode(ArbitrationSchedule.self, from: fixture)

    // 正在跑的那一场不算「下一次」
    precondition(tree.nextArbitrationDate(for: arbLeaf.id, schedule: oneSlot, now: insideFirst) == nil)
    // 但在它开始之前看，叶子与父级都该指向同一个时刻
    let beforeSlot = Date(timeIntervalSince1970: 1794140000)
    let expected = Date(timeIntervalSince1970: 1794146400)
    precondition(tree.nextArbitrationDate(for: arbLeaf.id, schedule: oneSlot, now: beforeSlot) == expected)
    precondition(tree.nextArbitrationDate(for: modeBranch.id, schedule: oneSlot, now: beforeSlot) == expected)
    print("✅ arbitration rows carry a next date: \(arbLeaf.title) @ \(expected)")
}

// ---- 通知计划：只有确定性事件能提前排。这里断言提前量、去重 id、预算上限，
//      刻意不碰 UserNotifications —— 那一层要在真机上才编得进去。
var wholeArb = WatchSelection()
wholeArb.select("arb")
print("· 通知计划：收集仲裁叶子")
let allArbLeaves = tree.coveredLeaves(wholeArb)
// 词典里有 mt 且带行星的节点里，12 种无尽任务合计 99 个
precondition(allArbLeaves.count >= 90, "仲裁叶子应在 90 以上，实际 \(allArbLeaves.count)")
precondition(allArbLeaves.allSatisfy { $0.isLeaf && $0.id.hasPrefix("arb|") },
             "选中仲裁根只该返回仲裁叶子")

if let planLeaf = allArbLeaves.first,
   let planNodeID = planLeaf.id.split(separator: "|").last.map(String.init) {
    let start = Date(timeIntervalSince1970: 1794146400)
    let planJSON = """
    {"builtAt":0,"slot":3600,"slots":[
     {"t":1794146400,"n":"\(planNodeID)"},
     {"t":1794175200,"n":"\(planNodeID)"}
    ]}
    """.data(using: .utf8)!
    let planSchedule = try JSONDecoder().decode(ArbitrationSchedule.self, from: planJSON)

    var oneLeaf = WatchSelection()
    oneLeaf.select(planLeaf.id)

    // 提前一小时看：两场都该排上，第一场提前 5 分钟
    let before = start.addingTimeInterval(-3600)
    let alerts = NotificationPlan.build(
        selection: oneLeaf, tree: tree, schedule: planSchedule, state: treeState, now: before
    )
    precondition(alerts.count == 2, "两场都该排，实际 \(alerts.count)")
    precondition(alerts[0].fireAt == start.addingTimeInterval(-NotificationPlan.arbitrationLead))
    precondition(alerts[0].id == "arb.\(planNodeID).\(Int(start.timeIntervalSince1970))",
                 "id 必须由节点和开始时刻组成，重复排才去得掉重：\(alerts[0].id)")
    precondition(alerts[0].body.contains("分钟后"), "正文要写清还有多久：\(alerts[0].body)")

    // 已经在跑的那场不该再提醒
    let insideSlot = start.addingTimeInterval(60)
    let late = NotificationPlan.build(
        selection: oneLeaf, tree: tree, schedule: planSchedule, state: treeState, now: insideSlot
    )
    precondition(late.count == 1, "过去的那场要跳过，实际 \(late.count)")
    precondition(late[0].fireAt > insideSlot)

    print("· 通知计划：预算截断")
    // 全选仲裁时按预算截断：iOS 只给 64 条待发，这里留 40
    var slots: [String] = []
    for (index, leaf) in allArbLeaves.prefix(20).enumerated() {
        guard let node = leaf.id.split(separator: "|").last.map(String.init) else { continue }
        slots.append("{\"t\":\(1794146400 + index * 3600),\"n\":\"\(node)\"}")
    }
    let wideJSON = "{\"builtAt\":0,\"slot\":3600,\"slots\":[\(slots.joined(separator: ","))]}"
        .data(using: .utf8)!
    let wide = try JSONDecoder().decode(ArbitrationSchedule.self, from: wideJSON)
    let capped = NotificationPlan.build(
        selection: wholeArb, tree: tree, schedule: wide, state: treeState,
        now: Date(timeIntervalSince1970: 1794140000), limit: 5
    )
    precondition(capped.count == 5, "超出预算要截到 5 条，实际 \(capped.count)")
    precondition(capped == capped.sorted { $0.fireAt < $1.fireAt }, "结果必须按触发时间升序")

    print("✅ NotificationPlan: 单节点 \(alerts.count) 条（提前 5 分钟），整树封顶 \(capped.count) 条")
}

// 周期：突击重置靠 worldState 里的 expiry 反推，不需要排程
print("· 通知计划：周期")
if let treeState = treeState, let sortieExpiry = treeState.Sorties?.first?.Expiry?.date {
    var cycleSelection = WatchSelection()
    cycleSelection.select("cycle|reset|sortie")
    let cycleAlerts = NotificationPlan.build(
        selection: cycleSelection, tree: tree, schedule: nil, state: treeState,
        now: sortieExpiry.addingTimeInterval(-7200)
    )
    precondition(cycleAlerts.count == 1, "突击重置应排出一条，实际 \(cycleAlerts.count)")
    precondition(cycleAlerts[0].fireAt == sortieExpiry.addingTimeInterval(-NotificationPlan.cycleLead))
    print("✅ NotificationPlan 周期：\(cycleAlerts[0].title) @ \(cycleAlerts[0].fireAt)")
}

// 星标的社区目标：带 expiry 的才能排，提前 30 分钟
print("· 通知计划：星标目标")
let starredGoal = WatchItem(
    key: "goal|test", label: "目标 · 测试", section: "社区目标",
    expiry: Date(timeIntervalSince1970: 1794146400)
)
let goalAlerts = NotificationPlan.build(
    selection: WatchSelection(), tree: tree, schedule: nil, state: nil,
    starred: [starredGoal], now: Date(timeIntervalSince1970: 1794140000)
)
precondition(goalAlerts.count == 1, "星标目标应排出一条，实际 \(goalAlerts.count)")
precondition(goalAlerts[0].fireAt == Date(timeIntervalSince1970: 1794144600))
precondition(NotificationPlan.build(
    selection: WatchSelection(), tree: tree, schedule: nil, state: nil,
    now: Date(timeIntervalSince1970: 1794140000)
).isEmpty, "什么都没选就不该有任何提醒")
print("✅ NotificationPlan 星标：\(goalAlerts[0].title) 提前 30 分钟")

// ---- 资产快照：真实那份在 .gitignore 里（含账号余额），仓库里只有裁剪过的
//      样例。CI 上没有真文件，就用样例验证解码路径；本地两种都该过。
let realPath = "\(currentDir)/WarframeWatch/Resources/InventoryData.json"
let samplePath = "\(currentDir)/WarframeWatch/Resources/InventoryData.sample.json"
let isSample = !FileManager.default.fileExists(atPath: realPath)
let invPath = isSample ? samplePath : realPath
guard FileManager.default.fileExists(atPath: invPath) else {
    fatalError("❌ 既没有 InventoryData.json 也没有 sample，两个路径都不存在")
}
let invRaw = try Data(contentsOf: URL(fileURLWithPath: invPath))
let inventory = try JSONDecoder().decode(InventoryData.self, from: invRaw)

// 样例裁到 15 套，真快照 162 套
precondition(inventory.sets.count > (isSample ? 8 : 100),
             "expected the prime set catalog, got \(inventory.sets.count)")
precondition(inventory.sets.allSatisfy { !$0.parts.isEmpty }, "every set must list its parts")
precondition(inventory.sets.contains { $0.isOwned }, "snapshot should contain at least one completed set")
precondition(inventory.relics.contains { $0.n > 0 }, "snapshot should contain owned relics")
precondition(inventory.relics.contains { $0.p > 0 }, "at least one relic should carry a market price")
precondition(inventory.sets.contains { $0.setPrice > 0 }, "at least one set should carry a market price")
print("✅ InventoryData: \(inventory.sets.count) sets "
      + "(\(inventory.totals.setsOwned) owned), "
      + "\(inventory.relics.count) relics, \(inventory.aya.items.count) aya items, "
      + "\(inventory.totals.loosePlat) p loose")

print("\n=== ALL TESTS PASSED SUCCESSFULLY ===")
