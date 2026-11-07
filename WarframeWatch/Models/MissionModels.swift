import Foundation

// MARK: - Alerts (限时警报)
public struct Alert: Codable, Identifiable {
    public var id: String { _id?.id ?? "\(MissionInfo?.location ?? "")_\(MissionInfo?.missionType ?? "")" }
    public let _id: WFOID?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let MissionInfo: AlertMissionInfo?
    public let Tag: String?
    public let ForceUnlock: Bool?
}

public struct AlertMissionInfo: Codable {
    public let location: String?
    public let missionType: String?
    public let faction: String?
    public let difficulty: Int?
    public let minEnemyLevel: Int?
    public let maxEnemyLevel: Int?
    public let descText: String?
    public let missionReward: MissionReward?
}

public struct MissionReward: Codable {
    public let credits: Int?
    public let xp: Int?
    public let items: [String]?
    public let countedItems: [CountedItem]?
    public let ItemType: String?
    public let ItemCount: Int?
    
    private enum CodingKeys: String, CodingKey {
        case credits, xp, items, countedItems, ItemType, ItemCount
    }
    
    public init(credits: Int? = nil, xp: Int? = nil, items: [String]? = nil, countedItems: [CountedItem]? = nil, ItemType: String? = nil, ItemCount: Int? = nil) {
        self.credits = credits
        self.xp = xp
        self.items = items
        self.countedItems = countedItems
        self.ItemType = ItemType
        self.ItemCount = ItemCount
    }
    
    public init(from decoder: Decoder) throws {
        // 1. If it's a keyed container (a standard JSON dictionary object)
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.credits = try? container.decodeIfPresent(Int.self, forKey: .credits)
            self.xp = try? container.decodeIfPresent(Int.self, forKey: .xp)
            self.items = try? container.decodeIfPresent([String].self, forKey: .items)
            self.countedItems = try? container.decodeIfPresent([CountedItem].self, forKey: .countedItems)
            self.ItemType = try? container.decodeIfPresent(String.self, forKey: .ItemType)
            self.ItemCount = try? container.decodeIfPresent(Int.self, forKey: .ItemCount)
            return
        }
        
        // 2. If it's an unkeyed container (DE often sends empty array `[]` when no rewards)
        if (try? decoder.unkeyedContainer()) != nil {
            self.credits = nil
            self.xp = nil
            self.items = nil
            self.countedItems = nil
            self.ItemType = nil
            self.ItemCount = nil
            return
        }
        
        // 3. Fallback
        self.credits = nil
        self.xp = nil
        self.items = nil
        self.countedItems = nil
        self.ItemType = nil
        self.ItemCount = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(credits, forKey: .credits)
        try container.encodeIfPresent(xp, forKey: .xp)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(countedItems, forKey: .countedItems)
        try container.encodeIfPresent(ItemType, forKey: .ItemType)
        try container.encodeIfPresent(ItemCount, forKey: .ItemCount)
    }
    
    public func containsKeyword(_ keyword: String) -> Bool {
        let kw = keyword.lowercased()
        if let items = items, items.contains(where: { $0.lowercased().contains(kw) }) { return true }
        if let counted = countedItems, counted.contains(where: { $0.ItemType.lowercased().contains(kw) }) { return true }
        if let itemType = ItemType, itemType.lowercased().contains(kw) { return true }
        return false
    }
}

public struct CountedItem: Codable, Identifiable {
    public var id: String { ItemType }
    public let ItemType: String
    public let ItemCount: Int
}

// MARK: - Invasions (入侵事件)
public struct Invasion: Codable, Identifiable {
    public var id: String { _id?.id ?? Node }
    public let _id: WFOID?
    public let Node: String
    public let Faction: String // Attacker
    public let DefenderFaction: String
    public let Count: Int
    public let Goal: Int?
    public let LocTag: String?
    public let Completed: Bool
    public let AttackerReward: MissionReward?
    public let DefenderReward: MissionReward?
    public let Activation: WFDate?
    
    public var targetGoal: Int {
        let g = Goal ?? 40000
        return g == 0 ? 40000 : g
    }
    
    /// Progress from 0.0 to 100.0%
    public var progressPct: Double {
        let g = Double(targetGoal)
        let c = Double(abs(Count))
        return min(100.0, max(0.0, (c / g) * 100.0))
    }
}

// MARK: - Void Fissures / Active Missions (虚空裂隙)
public struct ActiveMission: Codable, Identifiable {
    public var id: String { _id?.id ?? "\(Node)_\(MissionType)_\(Modifier)" }
    public let _id: WFOID?
    public let Node: String
    public let MissionType: String
    public let Modifier: String // VoidT1...VoidT6
    public let Hard: Bool?      // Steel Path (钢铁之路)
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Region: Int?
    public let Seed: Int?
    
    public var isSteelPath: Bool {
        Hard == true
    }
}

// MARK: - Void Storms (虚空风暴)
public struct VoidStorm: Codable, Identifiable {
    public var id: String { _id?.id ?? Node }
    public let _id: WFOID?
    public let Node: String
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let ActiveMissionTier: String // VoidT1...VoidT6
}

// MARK: - Community Goals (社区目标)
public struct Goal: Codable, Identifiable {
    public var id: String { _id?.id ?? (Tag ?? (Node ?? UUID().uuidString)) }
    public let _id: WFOID?
    public let Node: String?
    public let Tag: String?
    public let ScoreVar: String?
    public let Count: Double?
    public let Goal: Double?
    public let HealthPct: Double?
    public let Expiry: WFDate?
    public let Activation: WFDate?
    public let Desc: String?
    public let ToolTip: String?
    public let Reward: MissionReward?
    public let InterimGoals: [Double]?
    
    public var percentage: Double {
        if let hp = HealthPct {
            return hp * 100.0
        }
        if let g = Goal, g > 0, let c = Count {
            return min(100.0, (c / g) * 100.0)
        }
        return 0.0
    }
}
