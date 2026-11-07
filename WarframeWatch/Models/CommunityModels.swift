import Foundation

// MARK: - Syndicate Missions (集团任务)
public struct SyndicateMission: Codable, Identifiable {
    public var id: String { _id?.id ?? Tag }
    public let _id: WFOID?
    public let Tag: String
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let Seed: Int?
    public let Nodes: [String]?
}

// MARK: - Nightwave / Season Info (午夜电波 / 赛季)
public struct SeasonInfo: Codable {
    public let Season: Int?
    public let Phase: Int?
    public let AffiliationTag: String?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    public let ActiveChallenges: [SeasonChallenge]?
}

public struct SeasonChallenge: Codable, Identifiable {
    public var id: String { _id?.id ?? Challenge }
    public let _id: WFOID?
    public let Challenge: String
    public let Daily: Bool?
    public let Activation: WFDate?
    public let Expiry: WFDate?
    
    public var isDaily: Bool {
        Daily == true
    }
}

// MARK: - Flash Sales & Store Bundles (商城促销与组合包)
public struct FlashSale: Codable, Identifiable {
    public var id: String { TypeName }
    public let TypeName: String
    public let Discount: Int?
    public let PremiumOverride: Int? // Platinum price
    public let RegularOverride: Int? // Credits
    public let StartDate: WFDate?
    public let EndDate: WFDate?
    public let ShowInMarket: Bool?
    public let HideFromMarket: Bool?
    
    public var isExpired: Bool {
        guard let end = EndDate?.date else { return false }
        return Date() > end
    }
}

// MARK: - Official News & Community Events (官方公告与新闻)
public struct EventNews: Codable, Identifiable {
    public var id: String { _id?.id ?? (Prop ?? UUID().uuidString) }
    public let _id: WFOID?
    public let Messages: [EventMessage]?
    public let Prop: String? // URL link
    public let Priority: Bool?
    public let MobileOnly: Bool?
    public let Community: Bool?
    public let ImageUrl: String?
    public let Date: WFDate?
    
    public var preferredTitle: String {
        guard let msgs = Messages, !msgs.isEmpty else { return "社区公告" }
        if let zh = msgs.first(where: { $0.LanguageCode == "zh" || $0.LanguageCode == "tc" }), !zh.Message.isEmpty {
            return zh.Message
        }
        if let en = msgs.first(where: { $0.LanguageCode == "en" }), !en.Message.isEmpty {
            return en.Message
        }
        return msgs.first?.Message ?? "社区公告"
    }
}

public struct EventMessage: Codable {
    public let LanguageCode: String
    public let Message: String
}

// MARK: - PVP Challenge Instance (武形秘仪 Conclave)
public struct PVPChallengeInstance: Codable, Identifiable {
    public var id: String { _id?.id ?? (challengeTypeRefID ?? UUID().uuidString) }
    public let _id: WFOID?
    public let challengeTypeRefID: String?
    public let startDate: WFDate?
    public let endDate: WFDate?
    public let Category: String?
    public let PVPMode: String?
}
