import Foundation

public enum WatchCategory: String, CaseIterable, Identifiable, Codable {
    case all = "全部"
    case treasures = "核心珍宝"
    case speedrun = "效率裂隙"
    case cycles = "周期轮换"
    case invasions = "入侵战备"
    case specials = "特惠加成"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .treasures: return "sparkles"
        case .speedrun: return "bolt.badge.clock.fill"
        case .cycles: return "clock.arrow.circlepath"
        case .invasions: return "shield.lefthalf.filled"
        case .specials: return "gift.fill"
        }
    }
}

public enum TargetLiveState {
    case active(location: String, expiry: Date?, remainingSeconds: TimeInterval)
    case deterministic(nextDate: Date, timeRemaining: TimeInterval, note: String)
    case probabilistic(lastSeen: String, avgInterval: String, probabilityPct: Int, note: String)
    
    public var sortOrder: Int {
        switch self {
        case .active: return 0
        case .deterministic: return 1
        case .probabilistic: return 2
        }
    }
    
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

public struct EvaluatedWatchItem: Identifiable {
    public var id: String { item.id }
    public let item: WatchCatalogItem
    public let state: TargetLiveState
    public let isSubscribed: Bool
}

public struct WatchCatalogItem: Identifiable {
    public let id: String
    public let category: WatchCategory
    public let title: String
    public let subtitle: String
    public let icon: String
    public let frequencyHint: String
    public let evaluate: (WorldState) -> TargetLiveState
    
    public init(
        id: String,
        category: WatchCategory,
        title: String,
        subtitle: String,
        icon: String,
        frequencyHint: String,
        evaluate: @escaping (WorldState) -> TargetLiveState
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.frequencyHint = frequencyHint
        self.evaluate = evaluate
    }
}

public final class WatchCatalogDatabase {
    public static let shared = WatchCatalogDatabase()
    
    public let items: [WatchCatalogItem]
    
    private init() {
        self.items = [
            // ==================== 1. 核心珍宝 ====================
            WatchCatalogItem(
                id: "catalyst",
                category: .treasures,
                title: "Orokin 催化剂 (金土豆)",
                subtitle: "武器容量翻倍核心道具",
                icon: "sparkles",
                frequencyHint: "入侵/警报约 48~72h 一次",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("Catalyst") || r.containsKeyword("催化剂") {
                            let loc = alert.MissionInfo?.location ?? "警报节点"
                            let exp = alert.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "限时警报 · \(loc)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Catalyst") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Catalyst") ?? false) ||
                           (inv.AttackerReward?.containsKeyword("催化剂") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("催化剂") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "昨日", avgInterval: "48~72 小时", probabilityPct: 62, note: "未检测到活跃事件，结合历史频次拟合预测")
                }
            ),
            
            WatchCatalogItem(
                id: "reactor",
                category: .treasures,
                title: "Orokin 反应堆 (银土豆)",
                subtitle: "战甲/守护/载具容量翻倍核心道具",
                icon: "bolt.shield.fill",
                frequencyHint: "入侵/警报约 48~72h 一次",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("Reactor") || r.containsKeyword("反应堆") {
                            let loc = alert.MissionInfo?.location ?? "警报节点"
                            let exp = alert.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "限时警报 · \(loc)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Reactor") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Reactor") ?? false) ||
                           (inv.AttackerReward?.containsKeyword("反应堆") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("反应堆") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "2天前", avgInterval: "48~72 小时", probabilityPct: 78, note: "已超平均间隔，即将轮换触发")
                }
            ),
            
            WatchCatalogItem(
                id: "forma",
                category: .treasures,
                title: "Forma (福马蓝图 / 成品)",
                subtitle: "极化装备槽位改变极性必备",
                icon: "cube.fill",
                frequencyHint: "入侵中常态轮换，约 24~36h 一次",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Forma") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Forma") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "12小时前", avgInterval: "24~36 小时", probabilityPct: 50, note: "历史概率均值区间")
                }
            ),
            
            WatchCatalogItem(
                id: "exilus_warframe",
                category: .treasures,
                title: "战甲特殊功能槽连接器",
                subtitle: "解锁战甲特殊功能槽位 (Exilus)",
                icon: "square.split.diagonal.2x2",
                frequencyHint: "大型入侵争夺战掉落，约 3~5 天一次",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Exilus") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Exilus") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "3天前", avgInterval: "3~5 天", probabilityPct: 40, note: "历史周期估算")
                }
            ),
            
            WatchCatalogItem(
                id: "riven_sliver",
                category: .treasures,
                title: "裂罅碎石 (Riven Sliver)",
                subtitle: "钢铁之路与突击掉落，换取紫卡与钢铁精华",
                icon: "diamond.fill",
                frequencyHint: "钢铁之路 Eximus 掉落 / 警报常驻",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("RivenSliver") || r.containsKeyword("裂罅碎石") {
                            let loc = alert.MissionInfo?.location ?? "警报节点"
                            let exp = alert.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "限时警报 · \(loc)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "常态产出", avgInterval: "每日钢铁之路", probabilityPct: 95, note: "可在钢铁之路各生存/拦截节点常态获取")
                }
            ),
            
            // ==================== 2. 效率裂隙 ====================
            WatchCatalogItem(
                id: "fissure_t1_speed",
                category: .speedrun,
                title: "古纪 T1 捕获 / 歼灭 (速刷核桃)",
                subtitle: "全速开核桃首选，1 分钟一局",
                icon: "hare.fill",
                frequencyHint: "全天随机轮换，空窗通常 < 40 分钟",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT1" {
                        if f.MissionType == "MT_CAPTURE" || f.MissionType == "MT_EXTERMINATION" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_CAPTURE" ? "捕获" : "歼灭"
                            return .active(location: "\(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "25 分钟前", avgInterval: "35 分钟", probabilityPct: 85, note: "空窗期极短，即将刷新下一组轮换")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_t2_speed",
                category: .speedrun,
                title: "前纪 T2 捕获 / 歼灭 (速刷核桃)",
                subtitle: "前纪遗物快速开包",
                icon: "hare.fill",
                frequencyHint: "全天随机轮换，空窗通常 < 40 分钟",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT2" {
                        if f.MissionType == "MT_CAPTURE" || f.MissionType == "MT_EXTERMINATION" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_CAPTURE" ? "捕获" : "歼灭"
                            return .active(location: "\(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "15 分钟前", avgInterval: "35 分钟", probabilityPct: 75, note: "裂隙轮换周期拟合中")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_omnia",
                category: .speedrun,
                title: "全能裂隙 Omnia (全纪元自由选)",
                subtitle: "虚空覆盖与火卫二实验室，支持开启任意纪元遗物",
                icon: "circle.grid.cross.fill",
                frequencyHint: "火卫二 / 扎里曼实验室常态轮换",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT6" || f.Modifier == "Omnia" {
                        let exp = f.Expiry?.date
                        let rem = exp?.timeIntervalSinceNow ?? 0
                        return .active(location: "全能裂隙 · \(f.Node)", expiry: exp, remainingSeconds: rem)
                    }
                    return .probabilistic(lastSeen: "40 分钟前", avgInterval: "60 分钟", probabilityPct: 60, note: "全能裂隙多点轮替")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_sp_endless",
                category: .speedrun,
                title: "钢铁之路 裂隙 (生存 / 防御)",
                subtitle: "刷钢铁精华、裂隙精炼与资源双倍",
                icon: "shield.slash.fill",
                frequencyHint: "常驻多个节点进行中",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.isSteelPath {
                        if f.MissionType == "MT_SURVIVAL" || f.MissionType == "MT_DEFENSE" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_SURVIVAL" ? "生存" : "防御"
                            return .active(location: "钢铁 \(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "半小时前", avgInterval: "常态刷新", probabilityPct: 92, note: "高收益裂隙轮转")
                }
            ),
            
            // ==================== 3. 周期轮换 (100% 确定性) ====================
            WatchCatalogItem(
                id: "cetus_night",
                category: .cycles,
                title: "夜灵平野 · 入夜 (三傻捕猎)",
                subtitle: "兆力使 / 巨力使 / 水力使 捕捞狂热期",
                icon: "moon.stars.fill",
                frequencyHint: "每 150 分钟循环 (100m 白昼 / 50m 黑夜)",
                evaluate: { ws in
                    for s in ws.SyndicateMissions ?? [] where s.Tag == "CetusSyndicate" {
                        if let exp = s.Expiry?.date {
                            let rem = exp.timeIntervalSinceNow
                            if rem <= 3000 && rem > 0 {
                                return .active(location: "黑夜进行中 · 猎杀时刻 (剩余 \(Int(rem/60)) 分钟)", expiry: exp, remainingSeconds: rem)
                            } else if rem > 3000 {
                                let nightStart = exp.addingTimeInterval(-3000)
                                let untilNight = nightStart.timeIntervalSinceNow
                                return .deterministic(nextDate: nightStart, timeRemaining: max(0, untilNight), note: "白昼中，距离下次入夜猎杀")
                            }
                        }
                    }
                    return .deterministic(nextDate: Date().addingTimeInterval(3600), timeRemaining: 3600, note: "平原周期计算中")
                }
            ),
            
            WatchCatalogItem(
                id: "baro_trader",
                category: .cycles,
                title: "虚空商人 Baro Ki'Teer",
                subtitle: "每两周到港一次，带来专属 Prime MOD 与饰品",
                icon: "person.crop.rectangle.stack",
                frequencyHint: "每两周周五 21:00 进港，停留 48 小时",
                evaluate: { ws in
                    if let baro = ws.VoidTraders?.first {
                        if baro.isActive {
                            let exp = baro.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "已到港 · 停留于 \(baro.Node)", expiry: exp, remainingSeconds: rem)
                        } else if let act = baro.Activation?.date {
                            let rem = act.timeIntervalSinceNow
                            return .deterministic(nextDate: act, timeRemaining: max(0, rem), note: "虚空航行中，距离下次抵港")
                        }
                    }
                    return .deterministic(nextDate: Date().addingTimeInterval(86400 * 7), timeRemaining: 86400 * 7, note: "隔周五准时到港")
                }
            ),
            
            WatchCatalogItem(
                id: "sortie_daily_reset",
                category: .cycles,
                title: "每日突击重置",
                subtitle: "每天北京时间 00:00 准时刷新",
                icon: "shield.checkered",
                frequencyHint: "每日固定时间，必得紫卡/塑形块/雕塑",
                evaluate: { ws in
                    if let s = ws.Sorties?.first, let exp = s.Expiry?.date {
                        return .deterministic(nextDate: exp, timeRemaining: max(0, exp.timeIntervalSinceNow), note: "距离今日突击任务结算")
                    }
                    return .deterministic(nextDate: Date().addingTimeInterval(43200), timeRemaining: 43200, note: "每日固定周期")
                }
            ),
            
            WatchCatalogItem(
                id: "archon_hunt_weekly",
                category: .cycles,
                title: "执政官猎杀每周重置",
                subtitle: "每周一 00:00 刷新，必得执政官源力石 (红/蓝/黄)",
                icon: "flame.fill",
                frequencyHint: "每周一次核心战力强化来源",
                evaluate: { ws in
                    // Calculate next Monday 00:00 UTC
                    let cal = Calendar.current
                    let now = Date()
                    var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                    comps.weekday = 2 // Monday
                    comps.hour = 0
                    comps.minute = 0
                    comps.second = 0
                    var nextMonday = cal.date(from: comps) ?? now.addingTimeInterval(86400 * 3)
                    if nextMonday <= now {
                        nextMonday = cal.date(byAdding: .day, value: 7, to: nextMonday) ?? now.addingTimeInterval(86400 * 7)
                    }
                    let rem = nextMonday.timeIntervalSince(now)
                    return .deterministic(nextDate: nextMonday, timeRemaining: max(0, rem), note: "每周一 00:00 准时刷新")
                }
            ),
            
            // ==================== 4. 入侵战备 ====================
            WatchCatalogItem(
                id: "invasion_mutagen",
                category: .invasions,
                title: "突变原聚合物 (Mutagen Mass)",
                subtitle: "氏族道场生化实验室蓝图研发必备",
                icon: "testtube.2",
                frequencyHint: "Infested 派系入侵争夺战",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Mutagen") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Mutagen") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "8 小时前", avgInterval: "18 小时", probabilityPct: 65, note: "道场材料高频入侵中")
                }
            ),
            
            WatchCatalogItem(
                id: "invasion_weapon_parts",
                category: .invasions,
                title: "亡魂 / 破坏者 武器部件",
                subtitle: "卡拉克亡魂、德特昂破坏者等绝版武器部件",
                icon: "wrench.and.screwdriver.fill",
                frequencyHint: "克隆尼与科普斯阵营入侵争夺",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Wraith") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Wraith") ?? false) ||
                           (inv.AttackerReward?.containsKeyword("Vandal") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Vandal") ?? false) {
                            return .active(location: "阵营争夺 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "昨天", avgInterval: "2~3 天", probabilityPct: 40, note: "阵营战备不定期轮替")
                }
            ),
            
            // ==================== 5. 特惠与加成 ====================
            WatchCatalogItem(
                id: "global_buffs",
                category: .specials,
                title: "全服双倍加成活动",
                subtitle: "全服双倍经验 / 资源 / 现金",
                icon: "bolt.fill",
                frequencyHint: "版本更新、周年庆与官方活动突发",
                evaluate: { ws in
                    if let buff = ws.GlobalUpgrades?.first {
                        let exp = buff.ExpiryDate?.date
                        let rem = exp?.timeIntervalSinceNow ?? 0
                        return .active(location: "\(Int(buff.Value))× 倍率全服生效中", expiry: exp, remainingSeconds: rem)
                    }
                    return .probabilistic(lastSeen: "重大活动/版本", avgInterval: "突发加成", probabilityPct: 15, note: "官方直播与节庆期间开启")
                }
            ),
            
            WatchCatalogItem(
                id: "darvo_super_deal",
                category: .specials,
                title: "达尔沃大减价 (>50% 折扣)",
                subtitle: "中继站 Darvo 每日特惠战甲/武器半价以上",
                icon: "tag.fill",
                frequencyHint: "每日刷新，骨折折扣看脸",
                evaluate: { ws in
                    if let deal = ws.DailyDeals?.first {
                        if deal.Discount >= 50 {
                            let exp = deal.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "\(deal.Discount)% 折扣 · \(deal.StoreItem)", expiry: exp, remainingSeconds: rem)
                        } else {
                            let exp = deal.Expiry?.date ?? Date().addingTimeInterval(3600 * 12)
                            return .deterministic(nextDate: exp, timeRemaining: max(0, exp.timeIntervalSinceNow), note: "当前折扣 \(deal.Discount)%，距离下次进货")
                        }
                    }
                    return .probabilistic(lastSeen: "每日 0:00 进货", avgInterval: "24 小时", probabilityPct: 30, note: "高折扣随机概率")
                }
            )
        ]
    }
}
