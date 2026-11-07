import Foundation

// MARK: - Daily Sortie (突击)
public struct Sortie: Codable, Identifiable {
    public var id: String { _id?.id ?? Boss }
    public let _id: WFOID?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Reward: String?
    public let Seed: Int?
    public let Boss: String
    public let Variants: [SortieVariant]?
    public let Twitter: Bool?
    
    public init(Boss: String, Expiry: WFDate?, Variants: [SortieVariant]?, Reward: String? = nil) {
        self._id = nil
        self.Activation = nil
        self.Expiry = Expiry
        self.Reward = Reward
        self.Seed = nil
        self.Boss = Boss
        self.Variants = Variants
        self.Twitter = nil
    }
}

public struct SortieVariant: Codable, Identifiable {
    public var id: String { "\(node)_\(missionType)_\(modifierType)" }
    public let missionType: String
    public let modifierType: String
    public let node: String
    public let tileset: String?
    
    public init(missionType: String, modifierType: String, node: String, tileset: String? = nil) {
        self.missionType = missionType
        self.modifierType = modifierType
        self.node = node
        self.tileset = tileset
    }
}

// MARK: - Archon Hunt / LiteSorties (执政官猎杀)
public struct LiteSortie: Codable, Identifiable {
    public var id: String { _id?.id ?? Boss }
    public let _id: WFOID?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Reward: String?
    public let Boss: String
    public let Missions: [ArchonMission]?
}

public struct ArchonMission: Codable, Identifiable {
    public var id: String { "\(node)_\(missionType)" }
    public let missionType: String
    public let node: String
    
    enum CodingKeys: String, CodingKey {
        case missionType = "missionType"
        case node = "node"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.missionType = try container.decodeIfPresent(String.self, forKey: .missionType) ?? "MT_DEFAULT"
        self.node = try container.decodeIfPresent(String.self, forKey: .node) ?? ""
    }
}

// MARK: - Void Trader (虚空商人 Baro Ki'Teer)
public struct VoidTrader: Codable, Identifiable {
    public var id: String { _id?.id ?? Character }
    public let _id: WFOID?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Character: String
    public let Node: String
    public let Manifest: [VoidTraderItem]?
    
    public var isActive: Bool {
        guard let act = Activation?.date, let exp = Expiry?.date else { return false }
        let now = Date()
        return now >= act && now < exp
    }
}

public struct VoidTraderItem: Codable, Identifiable {
    public var id: String { ItemType }
    public let ItemType: String
    public let PrimePrice: Int?   // Ducats (杜卡德金币)
    public let RegularPrice: Int? // Credits (现金)
    public let Limit: Int?
}

// MARK: - Daily Deals (每日特惠)
public struct DailyDeal: Codable, Identifiable {
    public var id: String { StoreItem }
    public let StoreItem: String
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Discount: Int
    public let OriginalPrice: Int
    public let SalePrice: Int
    public let AmountTotal: Int
    public let AmountSold: Int
    
    public var soldPercentage: Double {
        guard AmountTotal > 0 else { return 0 }
        return Double(AmountSold) / Double(AmountTotal) * 100.0
    }
}

// MARK: - Global Upgrades (全局增益)
public struct GlobalUpgrade: Codable, Identifiable {
    public var id: String { _id?.id ?? UpgradeType }
    public let _id: WFOID?
    public let Activation: WFDate?
    public let ExpiryDate: WFDate?
    public let UpgradeType: String
    public let OperationType: String
    public let Value: Double
}

// MARK: - Prime Vault Trader (Prime 宝库商人 / 重生)
public struct PrimeVaultTrader: Codable, Identifiable {
    public var id: String { _id?.id ?? Node }
    public let _id: WFOID?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Node: String
    public let Manifest: [PrimeVaultItem]?
    public let EvergreenManifest: [PrimeVaultItem]?
}

public struct PrimeVaultItem: Codable, Identifiable {
    public var id: String { ItemType }
    public let ItemType: String
    public let PrimePrice: Int?   // Aya (阿耶)
    public let RegularPrice: Int? // Credits or other
}
