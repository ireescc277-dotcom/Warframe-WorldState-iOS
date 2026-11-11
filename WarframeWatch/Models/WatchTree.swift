import Foundation

// MARK: - Tree Node

public struct WatchNode: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let children: [WatchNode]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String = "circle",
        children: [WatchNode] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.children = children
    }

    public var isLeaf: Bool { children.isEmpty }
}

// MARK: - Live Hit

public struct WatchHit: Identifiable {
    public let id: String
    public let path: String
    public let family: String
    public let title: String
    public let detail: String
    public let expiry: Date?

    public init(id: String, path: String, family: String, title: String, detail: String, expiry: Date?) {
        self.id = id
        self.path = path
        self.family = family
        self.title = title
        self.detail = detail
        self.expiry = expiry
    }
}

// MARK: - Selection

public enum WatchSelectionState: Equatable {
    case off
    case on
    case mixed
}

/// Selection is stored as a set of *maximal selected paths*.
/// A node is covered when itself or one of its ancestors is in the set,
/// so selecting a whole branch stays a single string instead of thousands.
public struct WatchSelection {
    public private(set) var paths: Set<String>

    public init(paths: Set<String> = []) {
        self.paths = paths
    }

    public var count: Int { paths.count }
    public var isEmpty: Bool { paths.isEmpty }

    public func isCovered(_ path: String) -> Bool {
        if paths.contains(path) { return true }
        var cursor = path
        while let index = cursor.lastIndex(of: "|") {
            cursor = String(cursor[cursor.startIndex..<index])
            if paths.contains(cursor) { return true }
        }
        return false
    }

    public func hasSelectedDescendant(_ path: String) -> Bool {
        let prefix = path + "|"
        return paths.contains { $0.hasPrefix(prefix) }
    }

    public func state(of path: String) -> WatchSelectionState {
        if isCovered(path) { return .on }
        if hasSelectedDescendant(path) { return .mixed }
        return .off
    }

    public mutating func toggle(_ path: String, tree: WatchTreeIndex) {
        if state(of: path) == .on {
            deselect(path, tree: tree)
        } else {
            select(path)
        }
    }

    public mutating func select(_ path: String) {
        let prefix = path + "|"
        paths = Set(paths.filter { $0 != path && !$0.hasPrefix(prefix) })
        paths.insert(path)
    }

    /// Removing a branch that was selected through an ancestor has to give the
    /// rest of that ancestor back, otherwise unchecking one node would drop
    /// every sibling with it.
    private mutating func deselect(_ path: String, tree: WatchTreeIndex) {
        guard let cover = nearestCover(path) else { return }
        paths.remove(cover)
        if cover == path { return }

        var chain: [String] = []
        var cursor = path
        while cursor != cover {
            chain.append(cursor)
            guard let parent = tree.parent(of: cursor) else { break }
            cursor = parent
        }
        chain.reverse()

        var parentID = cover
        for step in chain {
            if let node = tree.node(parentID) {
                for child in node.children where child.id != step {
                    paths.insert(child.id)
                }
            }
            parentID = step
        }
    }

    private func nearestCover(_ path: String) -> String? {
        if paths.contains(path) { return path }
        var cursor = path
        while let index = cursor.lastIndex(of: "|") {
            cursor = String(cursor[cursor.startIndex..<index])
            if paths.contains(cursor) { return cursor }
        }
        return nil
    }
}

// MARK: - Tree Index

public final class WatchTreeIndex {

    private struct NamedKey {
        let key: String
        let name: String
    }

    private struct InvasionReward {
        let id: String
        let category: String
        let name: String
        let keywords: [String]
    }

    public let roots: [WatchNode]

    private let dict: DictionaryService
    private let nodeIndex: [String: WatchNode]
    private let parentIndex: [String: String]
    /// Star-chart node id -> arbitration leaf path. Built once so a live
    /// arbitration can be turned into a hit without walking the tree.
    private let arbitrationPaths: [String: String]

    // MARK: Static catalog data

    private static let eras: [NamedKey] = [
        NamedKey(key: "VoidT1", name: "古纪"),
        NamedKey(key: "VoidT2", name: "前纪"),
        NamedKey(key: "VoidT3", name: "中纪"),
        NamedKey(key: "VoidT4", name: "后纪"),
        NamedKey(key: "VoidT5", name: "安魂"),
        NamedKey(key: "VoidT6", name: "全能")
    ]

    private static let difficulties: [NamedKey] = [
        NamedKey(key: "nm", name: "普通"),
        NamedKey(key: "sp", name: "钢铁之路")
    ]

    /// Mission types that can carry a Void Fissure. Archwing and Railjack
    /// variants are deliberately absent — those nodes never host fissures, and
    /// including them would just add leaves that can never light up.
    private static let fissureModeKeys: [String] = [
        "MT_CAPTURE",
        "MT_EXTERMINATION",
        "MT_SURVIVAL",
        "MT_DEFENSE",
        "MT_MOBILE_DEFENSE",
        "MT_SABOTAGE",
        "MT_RESCUE",
        "MT_INTEL",
        "MT_TERRITORY",
        "MT_ARTIFACT",
        "MT_EXCAVATE",
        "MT_HIVE",
        "MT_EVACUATION",
        "MT_PURIFY",
        "MT_MIRROR_DEFENSE",
        "MT_CORRUPTION",
        "MT_VOID_CASCADE",
        "MT_VOID_ARMAGEDDON",
        "MT_ALCHEMY"
    ]

    /// Arbitration only ever runs endless missions. Per the wiki the rotation is
    /// Alchemy, Defection, Defense, Disruption, Excavation, Infested Salvage,
    /// Interception, Mirror Defense, Survival, Void Cascade, Void Flood and
    /// Void Armageddon — nothing else, which is why this list is shorter than
    /// `fissureModeKeys` rather than equal to it.
    private static let arbitrationModeKeys: [String] = [
        "MT_SURVIVAL",
        "MT_DEFENSE",
        "MT_TERRITORY",
        "MT_EXCAVATE",
        "MT_ARTIFACT",
        "MT_EVACUATION",
        "MT_PURIFY",
        "MT_MIRROR_DEFENSE",
        "MT_CORRUPTION",
        "MT_VOID_CASCADE",
        "MT_VOID_ARMAGEDDON",
        "MT_ALCHEMY"
    ]

    private static let planetOrder: [String] = [
        "地球", "水星", "金星", "火星", "火卫一", "火卫二", "谷神星",
        "木星", "欧罗巴", "土星", "天王星", "海王星", "冥王星",
        "赛德娜", "阋神星", "月球", "虚空", "赤毒要塞", "扎里曼", "杜维里"
    ]

    private static let invasionCategories: [NamedKey] = [
        NamedKey(key: "potato", name: "土豆"),
        NamedKey(key: "forma", name: "塑形块"),
        NamedKey(key: "exilus", name: "特殊功能槽"),
        NamedKey(key: "weapon", name: "武器部件"),
        NamedKey(key: "resource", name: "道场材料"),
        NamedKey(key: "rare", name: "稀有物资")
    ]

    private static let invasionRewards: [InvasionReward] = [
        InvasionReward(id: "catalyst", category: "potato", name: "奥罗金催化剂", keywords: ["Catalyst", "催化剂"]),
        InvasionReward(id: "reactor", category: "potato", name: "奥罗金反应堆", keywords: ["Reactor", "反应堆"]),
        InvasionReward(id: "forma", category: "forma", name: "塑形块 (Forma)", keywords: ["Forma"]),
        InvasionReward(id: "exilus_wf", category: "exilus", name: "战甲特殊功能槽连接器", keywords: ["ExilusAdapter", "Exilus"]),
        InvasionReward(id: "exilus_wp", category: "exilus", name: "武器特殊功能槽连接器", keywords: ["WeaponExilus"]),
        InvasionReward(id: "karak_wraith", category: "weapon", name: "卡拉卡·亡魂 部件", keywords: ["KarakWraith"]),
        InvasionReward(id: "dera_vandal", category: "weapon", name: "德拉·破坏者 部件", keywords: ["DeraVandal"]),
        InvasionReward(id: "strun_wraith", category: "weapon", name: "斯特朗·亡魂 部件", keywords: ["StrunWraith"]),
        InvasionReward(id: "snipetron_vandal", category: "weapon", name: "狙击特昂·破坏者 部件", keywords: ["SnipetronVandal"]),
        InvasionReward(id: "latron_wraith", category: "weapon", name: "拉特昂·亡魂 部件", keywords: ["LatronWraith"]),
        InvasionReward(id: "twin_vipers_wraith", category: "weapon", name: "双子蝰蛇·亡魂 部件", keywords: ["TwinVipersWraith"]),
        InvasionReward(id: "sheev", category: "weapon", name: "希芙 部件", keywords: ["Sheev"]),
        InvasionReward(id: "mutagen_mass", category: "resource", name: "突变原聚合物", keywords: ["Mutagen"]),
        InvasionReward(id: "fieldron", category: "resource", name: "电磁力导管", keywords: ["Fieldron"]),
        InvasionReward(id: "detonite", category: "resource", name: "爆燃喷射器", keywords: ["Detonite"]),
        InvasionReward(id: "riven_sliver", category: "rare", name: "裂罅碎石", keywords: ["RivenSliver", "裂罅碎石"]),
        InvasionReward(id: "kavat_code", category: "rare", name: "库娃遗传密码", keywords: ["KavatCode", "Kavat"]),
        InvasionReward(id: "nitain", category: "rare", name: "泥炭萃取物", keywords: ["Nitain"]),
        InvasionReward(id: "orokin_cell", category: "rare", name: "奥罗金电池", keywords: ["OrokinCell"])
    ]

    // MARK: Init

    public init(dictionary: DictionaryService = .shared) {
        self.dict = dictionary

        let fissures = WatchTreeIndex.buildFissures(dict: dictionary)
        let arbitrations = WatchTreeIndex.buildArbitrations(dict: dictionary)
        let invasions = WatchTreeIndex.buildInvasions()
        let storms = WatchTreeIndex.buildStorms()
        let cycles = WatchTreeIndex.buildCycles()
        let all = [fissures, arbitrations, invasions, storms, cycles]
        self.roots = all

        var index: [String: WatchNode] = [:]
        var parents: [String: String] = [:]
        WatchTreeIndex.indexNodes(all, parent: nil, index: &index, parents: &parents)
        self.nodeIndex = index
        self.parentIndex = parents

        // Leaves look like `arb|<mode>|<planet>|<nodeID>`; the trailing segment
        // is the star-chart node id the third-party feed hands us.
        var arbPaths: [String: String] = [:]
        for (id, node) in index where node.isLeaf && id.hasPrefix("arb|") {
            guard let nodeID = id.split(separator: "|").last else { continue }
            arbPaths[String(nodeID)] = id
        }
        self.arbitrationPaths = arbPaths
    }

    private static func indexNodes(
        _ nodes: [WatchNode],
        parent: String?,
        index: inout [String: WatchNode],
        parents: inout [String: String]
    ) {
        for node in nodes {
            index[node.id] = node
            if let parent = parent {
                parents[node.id] = parent
            }
            indexNodes(node.children, parent: node.id, index: &index, parents: &parents)
        }
    }

    // MARK: Access

    public var nodeCount: Int { nodeIndex.count }

    public func node(_ id: String) -> WatchNode? {
        nodeIndex[id]
    }

    public func parent(of id: String) -> String? {
        parentIndex[id]
    }

    /// 被选中范围覆盖到的叶子。选中父级时整棵子树都算，所以这里走一遍树、
    /// 不带选中后代的枝直接剪掉——比起先取全量 3102 个叶子再逐个 isCovered
    /// 少一大截，排提醒每次刷新都要跑。
    public func coveredLeaves(_ selection: WatchSelection) -> [WatchNode] {
        guard !selection.isEmpty else { return [] }
        var leaves: [WatchNode] = []

        func walk(_ node: WatchNode) {
            if !selection.isCovered(node.id) && !selection.hasSelectedDescendant(node.id) {
                return
            }
            if node.isLeaf {
                leaves.append(node)
                return
            }
            for child in node.children {
                walk(child)
            }
        }

        for root in roots {
            walk(root)
        }
        return leaves
    }

    public func breadcrumb(of id: String) -> String {
        var parts: [String] = []
        var cursor: String? = id
        while let current = cursor {
            if let node = nodeIndex[current] {
                parts.append(node.title)
            }
            cursor = parentIndex[current]
        }
        return parts.reversed().joined(separator: " / ")
    }

    // MARK: Build — Fissures (纪元 / 难度 / 任务类型 / 节点)

    /// Railjack nodes never host a fissure or an arbitration — the only
    /// Railjack-specific event is a Void Storm, which has its own root.
    private static func isGroundNode(_ nodeID: String) -> Bool {
        !nodeID.hasPrefix("CrewBattleNode")
    }

    private static func buildFissures(dict: DictionaryService) -> WatchNode {
        var eraNodes: [WatchNode] = []

        for era in eras {
            var difficultyNodes: [WatchNode] = []

            for difficulty in difficulties {
                var modeNodes: [WatchNode] = []

                for modeKey in fissureModeKeys {
                    let nodeIDs = dict.nodeIDs(ofMissionType: modeKey)
                        .filter { dict.nodePlanet($0) != nil && isGroundNode($0) }
                        .sorted { dict.nodeName($0) < dict.nodeName($1) }

                    let leaves = nodeIDs.map { nodeID in
                        WatchNode(
                            id: "fis|\(era.key)|\(difficulty.key)|\(modeKey)|\(nodeID)",
                            title: dict.nodeName(nodeID),
                            icon: "circle"
                        )
                    }

                    modeNodes.append(WatchNode(
                        id: "fis|\(era.key)|\(difficulty.key)|\(modeKey)",
                        title: dict.missionType(modeKey),
                        subtitle: leaves.isEmpty ? "任意节点" : "\(leaves.count) 个节点",
                        icon: "circle",
                        children: leaves
                    ))
                }

                difficultyNodes.append(WatchNode(
                    id: "fis|\(era.key)|\(difficulty.key)",
                    title: difficulty.name,
                    subtitle: "\(modeNodes.count) 种任务",
                    icon: difficulty.key == "sp" ? "shield.slash.fill" : "shield.fill",
                    children: modeNodes
                ))
            }

            eraNodes.append(WatchNode(
                id: "fis|\(era.key)",
                title: era.name,
                subtitle: "\(difficultyNodes.count) 种难度",
                icon: "circle",
                children: difficultyNodes
            ))
        }

        return WatchNode(
            id: "fis",
            title: "虚空裂隙",
            subtitle: "纪元 / 难度 / 任务类型 / 节点",
            icon: "bolt.badge.clock",
            children: eraNodes
        )
    }

    // MARK: Build — Arbitration (任务类型 / 星球 / 节点)

    private static func buildArbitrations(dict: DictionaryService) -> WatchNode {
        var typeNodes: [WatchNode] = []

        for modeKey in arbitrationModeKeys {
            let nodeIDs = dict.nodeIDs(ofMissionType: modeKey)
                .filter { dict.nodePlanet($0) != nil && isGroundNode($0) }

            var byPlanet: [String: [String]] = [:]
            for nodeID in nodeIDs {
                let planet = dict.nodePlanet(nodeID) ?? "其他"
                byPlanet[planet, default: []].append(nodeID)
            }

            let planets = byPlanet.keys.sorted { lhs, rhs in
                let left = planetOrder.firstIndex(of: lhs) ?? Int.max
                let right = planetOrder.firstIndex(of: rhs) ?? Int.max
                if left != right { return left < right }
                return lhs < rhs
            }

            let planetNodes = planets.map { planet -> WatchNode in
                let ids = (byPlanet[planet] ?? []).sorted { dict.nodeName($0) < dict.nodeName($1) }
                let leaves = ids.map { nodeID in
                    WatchNode(
                        id: "arb|\(modeKey)|\(planet)|\(nodeID)",
                        title: dict.nodeName(nodeID),
                        icon: "circle"
                    )
                }
                return WatchNode(
                    id: "arb|\(modeKey)|\(planet)",
                    title: planet,
                    subtitle: "\(leaves.count) 个节点",
                    icon: "globe.asia.australia.fill",
                    children: leaves
                )
            }

            typeNodes.append(WatchNode(
                id: "arb|\(modeKey)",
                title: dict.missionType(modeKey),
                subtitle: "\(nodeIDs.count) 个节点",
                icon: "circle",
                children: planetNodes
            ))
        }

        return WatchNode(
            id: "arb",
            title: "仲裁",
            subtitle: "任务类型 / 星球 / 节点",
            icon: "shield.lefthalf.filled",
            children: typeNodes
        )
    }

    // MARK: Build — Invasions (奖励类别 / 奖励)

    private static func buildInvasions() -> WatchNode {
        var categoryNodes: [WatchNode] = []

        for category in invasionCategories {
            let rewards = invasionRewards.filter { $0.category == category.key }
            guard !rewards.isEmpty else { continue }

            let leaves = rewards.map { reward in
                WatchNode(
                    id: "inv|\(category.key)|\(reward.id)",
                    title: reward.name,
                    icon: "gift.fill"
                )
            }

            categoryNodes.append(WatchNode(
                id: "inv|\(category.key)",
                title: category.name,
                subtitle: "\(leaves.count) 项",
                icon: "shippingbox.fill",
                children: leaves
            ))
        }

        return WatchNode(
            id: "inv",
            title: "入侵奖励",
            subtitle: "奖励类别 / 具体奖励",
            icon: "shield.lefthalf.filled",
            children: categoryNodes
        )
    }

    // MARK: Build — Void Storms (纪元)

    private static func buildStorms() -> WatchNode {
        let leaves = eras.map { era in
            WatchNode(
                id: "storm|\(era.key)",
                title: era.name,
                subtitle: "任意节点",
                icon: "wind"
            )
        }
        return WatchNode(
            id: "storm",
            title: "虚空风暴",
            subtitle: "纪元（节点池未公开）",
            icon: "wind",
            children: leaves
        )
    }

    // MARK: Build — Cycles

    private static func buildCycles() -> WatchNode {
        let cetus = WatchNode(
            id: "cycle|cetus",
            title: "希图斯 / 夜灵平野",
            icon: "moon.stars.fill",
            children: [
                WatchNode(id: "cycle|cetus|night", title: "黑夜 · 三傻猎杀", subtitle: "约 50 分钟", icon: "moon.fill"),
                WatchNode(id: "cycle|cetus|day", title: "白昼 · 赏金 / 采矿", subtitle: "约 100 分钟", icon: "sun.max.fill")
            ]
        )

        let vallis = WatchNode(
            id: "cycle|vallis",
            title: "奥布山谷",
            icon: "thermometer.sun.fill",
            children: [
                WatchNode(id: "cycle|vallis|warm", title: "暖温期 · 稀有机械鱼", subtitle: "约 6 分 40 秒", icon: "fish.fill")
            ]
        )

        let baro = WatchNode(
            id: "cycle|baro",
            title: "虚空商人",
            icon: "person.crop.rectangle.stack.fill",
            children: [
                WatchNode(id: "cycle|baro|arrival", title: "Baro 到港", subtitle: "隔周停留 48 小时", icon: "shippingbox.fill")
            ]
        )

        let resets = WatchNode(
            id: "cycle|reset",
            title: "重置",
            icon: "arrow.clockwise",
            children: [
                WatchNode(id: "cycle|reset|sortie", title: "每日突击重置", subtitle: "北京时间 00:00", icon: "shield.checkered"),
                WatchNode(id: "cycle|reset|archon", title: "执政官猎杀重置", subtitle: "每周一 00:00", icon: "flame.fill")
            ]
        )

        return WatchNode(
            id: "cycle",
            title: "周期与重置",
            subtitle: "确定性事件",
            icon: "clock.arrow.circlepath",
            children: [cetus, vallis, baro, resets]
        )
    }

    // MARK: - Live matching

    public static func canonicalFissureMode(_ raw: String) -> String? {
        if raw == "MT_DISRUPTION" { return "MT_ARTIFACT" }
        return fissureModeKeys.contains(raw) ? raw : nil
    }

    public func liveHits(in state: WorldState, now: Date = Date()) -> [WatchHit] {
        var hits: [WatchHit] = []
        hits.append(contentsOf: fissureHits(state))
        hits.append(contentsOf: invasionHits(state))
        hits.append(contentsOf: stormHits(state))
        hits.append(contentsOf: cycleHits(state, now: now))
        return hits
    }

    /// Arbitration is not in DE's feed, so it is injected separately instead of
    /// being derived from `WorldState`.
    public func arbitrationHit(_ info: ArbitrationInfo?) -> WatchHit? {
        guard let info, !info.isPlaceholder,
              let nodeID = info.nodeKey,
              let path = arbitrationPaths[nodeID] else { return nil }
        return arbitrationHit(nodeID: nodeID, path: path, expiry: info.expiryDate)
    }

    /// 排程版本：browse.wf 的轮换表是确定性的，比第三方镜像更可靠，
    /// 而且它连「现在这一场什么时候结束」都直接给得出来。
    public func arbitrationHit(schedule: ArbitrationSchedule?, now: Date = Date()) -> WatchHit? {
        guard let schedule, let current = schedule.current(at: now),
              let path = arbitrationPaths[current.node] else { return nil }
        return arbitrationHit(nodeID: current.node, path: path, expiry: current.end)
    }

    private func arbitrationHit(nodeID: String, path: String, expiry: Date?) -> WatchHit {
        let parts = path.split(separator: "|")
        let modeKey = parts.count > 1 ? String(parts[1]) : ""
        return WatchHit(
            id: path,
            path: path,
            family: "仲裁",
            title: "仲裁 · \(dict.missionType(modeKey))",
            detail: dict.nodeName(nodeID),
            expiry: expiry
        )
    }

    /// 界面上那一行（任务类型 / 星球 / 具体节点）下一次有仲裁的时间。
    /// 分组节点取整棵子树里最近的一次，这样「土星」这一行本身也有意义。
    public func nextArbitrationDate(
        for id: String,
        schedule: ArbitrationSchedule?,
        now: Date = Date()
    ) -> Date? {
        guard let schedule, id.hasPrefix("arb|") else { return nil }
        var best: Date?
        for path in arbitrationLeafPaths(under: id) {
            guard let nodeID = path.split(separator: "|").last.map(String.init),
                  let date = schedule.nextDate(forNode: nodeID, after: now) else { continue }
            if best == nil || date < best! { best = date }
        }
        return best
    }

    /// 星图节点 → 树上那条仲裁叶子的路径。界面用它拆出任务类型与星球。
    public func arbitrationPath(for nodeID: String) -> String? {
        arbitrationPaths[nodeID]
    }

    private func arbitrationLeafPaths(under id: String) -> [String] {
        guard let node = nodeIndex[id] else { return [] }
        if node.isLeaf { return [id] }
        return node.children.flatMap { arbitrationLeafPaths(under: $0.id) }
    }

    private func fissureHits(_ state: WorldState) -> [WatchHit] {
        guard let fissures = state.ActiveMissions else { return [] }
        var hits: [WatchHit] = []

        for fissure in fissures {
            guard let mode = WatchTreeIndex.canonicalFissureMode(fissure.MissionType) else { continue }
            let difficulty = fissure.isSteelPath ? "sp" : "nm"
            let path = "fis|\(fissure.Modifier)|\(difficulty)|\(mode)|\(fissure.Node)"
            let era = dict.tierName(fissure.Modifier)
            let modeName = dict.missionType(mode)
            let prefix = fissure.isSteelPath ? "钢铁之路 · " : ""

            hits.append(WatchHit(
                id: path,
                path: path,
                family: "虚空裂隙",
                title: "\(era) · \(modeName)",
                detail: "\(prefix)\(dict.nodeName(fissure.Node))",
                expiry: fissure.Expiry?.date
            ))
        }

        return hits
    }

    private func invasionHits(_ state: WorldState) -> [WatchHit] {
        guard let invasions = state.Invasions else { return [] }
        var hits: [WatchHit] = []

        for invasion in invasions where !invasion.Completed {
            let attacker = dict.faction(invasion.Faction)
            let defender = dict.faction(invasion.DefenderFaction)
            let node = dict.nodeName(invasion.Node)

            for reward in WatchTreeIndex.invasionRewards {
                guard WatchTreeIndex.invasion(invasion, contains: reward.keywords) else { continue }
                let path = "inv|\(reward.category)|\(reward.id)"
                hits.append(WatchHit(
                    id: "\(invasion.id)|\(reward.id)",
                    path: path,
                    family: "入侵",
                    title: reward.name,
                    detail: "\(attacker) → \(defender) · \(node)",
                    expiry: nil
                ))
            }
        }

        return hits
    }

    private static func invasion(_ invasion: Invasion, contains keywords: [String]) -> Bool {
        if let reward = invasion.AttackerReward {
            for keyword in keywords where reward.containsKeyword(keyword) {
                return true
            }
        }
        if let reward = invasion.DefenderReward {
            for keyword in keywords where reward.containsKeyword(keyword) {
                return true
            }
        }
        return false
    }

    private func stormHits(_ state: WorldState) -> [WatchHit] {
        guard let storms = state.VoidStorms else { return [] }
        return storms.map { storm in
            let path = "storm|\(storm.ActiveMissionTier)"
            return WatchHit(
                id: "\(path)|\(storm.Node)",
                path: path,
                family: "虚空风暴",
                title: "\(dict.tierName(storm.ActiveMissionTier)) 风暴",
                detail: dict.nodeName(storm.Node),
                expiry: storm.Expiry?.date
            )
        }
    }

    private func cycleHits(_ state: WorldState, now: Date) -> [WatchHit] {
        var hits: [WatchHit] = []

        if let expiry = cetusExpiry(state) {
            let remaining = expiry.timeIntervalSince(now)
            if remaining > 0 && remaining <= 3000 {
                hits.append(WatchHit(
                    id: "cycle|cetus|night",
                    path: "cycle|cetus|night",
                    family: "周期",
                    title: "夜灵平野 · 黑夜",
                    detail: "三傻猎杀期",
                    expiry: expiry
                ))
            } else if remaining > 3000 {
                hits.append(WatchHit(
                    id: "cycle|cetus|day",
                    path: "cycle|cetus|day",
                    family: "周期",
                    title: "夜灵平野 · 白昼",
                    detail: "赏金 / 采矿 / 捕鱼",
                    expiry: expiry.addingTimeInterval(-3000)
                ))
            }
        }

        let position = vallisPosition(now)
        if position < 400 {
            hits.append(WatchHit(
                id: "cycle|vallis|warm",
                path: "cycle|vallis|warm",
                family: "周期",
                title: "奥布山谷 · 暖温期",
                detail: "稀有机械鱼群",
                expiry: now.addingTimeInterval(400 - position)
            ))
        }

        if let baro = state.VoidTraders?.first, baro.isActive {
            hits.append(WatchHit(
                id: "cycle|baro|arrival",
                path: "cycle|baro|arrival",
                family: "周期",
                title: "虚空商人 · 已到港",
                detail: baro.Node,
                expiry: baro.Expiry?.date
            ))
        }

        return hits
    }

    // MARK: - Next occurrence (cycles only)

    public func nextOccurrence(
        for id: String,
        in state: WorldState,
        schedule: ArbitrationSchedule? = nil,
        now: Date = Date()
    ) -> Date? {
        // 仲裁有确定排程，不需要从 worldState 推。
        if id.hasPrefix("arb|") {
            return nextArbitrationDate(for: id, schedule: schedule, now: now)
        }

        switch id {
        case "cycle|cetus|night":
            guard let expiry = cetusExpiry(state) else { return nil }
            let remaining = expiry.timeIntervalSince(now)
            if remaining > 0 && remaining <= 3000 { return nil }
            return remaining > 3000 ? expiry.addingTimeInterval(-3000) : expiry.addingTimeInterval(6000)

        case "cycle|cetus|day":
            guard let expiry = cetusExpiry(state) else { return nil }
            return expiry.timeIntervalSince(now) > 3000 ? nil : expiry

        case "cycle|vallis|warm":
            let position = vallisPosition(now)
            return position < 400 ? nil : now.addingTimeInterval(1600 - position)

        case "cycle|baro|arrival":
            guard let baro = state.VoidTraders?.first else { return nil }
            return baro.isActive ? nil : baro.Activation?.date

        case "cycle|reset|sortie":
            return state.Sorties?.first?.Expiry?.date

        case "cycle|reset|archon":
            return state.LiteSorties?.first?.Expiry?.date

        default:
            return nil
        }
    }

    private func cetusExpiry(_ state: WorldState) -> Date? {
        guard let mission = state.SyndicateMissions?.first(where: { $0.Tag == "CetusSyndicate" }) else {
            return nil
        }
        return mission.Expiry?.date
    }

    private func vallisPosition(_ now: Date) -> TimeInterval {
        let epoch: TimeInterval = 1542067200
        let length: TimeInterval = 1600
        let raw = (now.timeIntervalSince1970 - epoch).truncatingRemainder(dividingBy: length)
        return raw < 0 ? raw + length : raw
    }
}

// MARK: - Server Push Alert Level

/// 服务器那条推送（裂隙 / 入侵 / 虚空风暴）的打断强度。
///
/// 这四个值原样传给 Bark 的 `level`，对应 APNs 的四档中断级别。它管的是
/// 「不知道什么时候会冒出来」的事件；仲裁和周期由本地排程负责，和这里无关。
public enum WatchAlertLevel: String, CaseIterable, Identifiable {
    case passive
    case active
    case timeSensitive
    case critical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .passive: return "静默"
        case .active: return "默认"
        case .timeSensitive: return "时效性"
        case .critical: return "关键"
        }
    }

    public var detail: String {
        switch self {
        case .passive: return "只进通知中心，不亮屏也不响"
        case .active: return "亮屏、横幅、响一声"
        case .timeSensitive: return "专注模式也照常弹，静音位仍然不响"
        case .critical: return "绕过静音开关强制响铃，需要 Bark 里打开「重要警告」"
        }
    }

    /// 用两三个字说清差别，放不下整段说明时用。
    public var short: String {
        switch self {
        case .passive: return "不响"
        case .active: return "响一声"
        case .timeSensitive: return "穿专注"
        case .critical: return "绕静音"
        }
    }
}
