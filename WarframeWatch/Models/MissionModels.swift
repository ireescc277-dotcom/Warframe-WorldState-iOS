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
