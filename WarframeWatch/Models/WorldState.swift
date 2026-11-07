import Foundation

/// Root Warframe WorldState Data Model
public struct WorldState: Codable {
    public let WorldSeed: String?
    public let Version: Int?
    public let MobileVersion: String?
    public let BuildLabel: String?
    public let Time: WFDate?
    
    // Focus
    public let Sorties: [Sortie]?
    public let LiteSorties: [LiteSortie]?
    public let VoidTraders: [VoidTrader]?
    public let PrimeVaultTraders: [PrimeVaultTrader]?
    public let DailyDeals: [DailyDeal]?
    public let GlobalUpgrades: [GlobalUpgrade]?
    
    // Missions
    public let Alerts: [Alert]?
    public let Invasions: [Invasion]?
    public let ActiveMissions: [ActiveMission]? // Void Fissures
    public let VoidStorms: [VoidStorm]?
    public let Goals: [Goal]?
    
    // Community & Seasons
    public let SyndicateMissions: [SyndicateMission]?
    public let SeasonInfo: SeasonInfo?
    public let FlashSales: [FlashSale]?
    public let Events: [EventNews]?
    public let PVPChallengeInstances: [PVPChallengeInstance]?
    
    // Additional Raw fields
    public let Tmp: String?
    
    public init(
        WorldSeed: String? = nil,
        Version: Int? = nil,
        MobileVersion: String? = nil,
        BuildLabel: String? = nil,
        Time: WFDate? = nil,
        Sorties: [Sortie]? = nil,
        LiteSorties: [LiteSortie]? = nil,
        VoidTraders: [VoidTrader]? = nil,
        PrimeVaultTraders: [PrimeVaultTrader]? = nil,
        DailyDeals: [DailyDeal]? = nil,
        GlobalUpgrades: [GlobalUpgrade]? = nil,
        Alerts: [Alert]? = nil,
        Invasions: [Invasion]? = nil,
        ActiveMissions: [ActiveMission]? = nil,
        VoidStorms: [VoidStorm]? = nil,
        Goals: [Goal]? = nil,
        SyndicateMissions: [SyndicateMission]? = nil,
        SeasonInfo: SeasonInfo? = nil,
        FlashSales: [FlashSale]? = nil,
        Events: [EventNews]? = nil,
        PVPChallengeInstances: [PVPChallengeInstance]? = nil,
        Tmp: String? = nil
    ) {
        self.WorldSeed = WorldSeed
        self.Version = Version
        self.MobileVersion = MobileVersion
        self.BuildLabel = BuildLabel
        self.Time = Time
        self.Sorties = Sorties
        self.LiteSorties = LiteSorties
        self.VoidTraders = VoidTraders
        self.PrimeVaultTraders = PrimeVaultTraders
        self.DailyDeals = DailyDeals
        self.GlobalUpgrades = GlobalUpgrades
        self.Alerts = Alerts
        self.Invasions = Invasions
        self.ActiveMissions = ActiveMissions
        self.VoidStorms = VoidStorms
        self.Goals = Goals
        self.SyndicateMissions = SyndicateMissions
        self.SeasonInfo = SeasonInfo
        self.FlashSales = FlashSales
        self.Events = Events
        self.PVPChallengeInstances = PVPChallengeInstances
        self.Tmp = Tmp
    }
}
