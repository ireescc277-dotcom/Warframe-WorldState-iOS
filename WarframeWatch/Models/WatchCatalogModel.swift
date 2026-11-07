import Foundation

public enum WatchCategory: String, CaseIterable, Identifiable, Codable {
    case all = "全部"
    case treasures = "核心资产"
    case cycles = "周期与重置"
    case speedrun = "效率裂隙"
    case invasions = "入侵战备"
    case specials = "特惠与活动"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .treasures: return "sparkles"
        case .cycles: return "clock.arrow.circlepath"
        case .speedrun: return "bolt.badge.clock"
        case .invasions: return "shield.lefthalf.filled"
        case .specials: return "gift"
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
            // ==================== 1. 核心资产 (官方规范译名) ====================
            WatchCatalogItem(
                id: "catalyst",
                category: .treasures,
                title: "奥罗金催化剂 (金土豆)",
                subtitle: "武器容量翻倍核心道具",
                icon: "sparkles",
                frequencyHint: "入侵/警报约 48~72h 一次",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("Catalyst") || r.containsKeyword("催化剂") {
                            let loc = alert.MissionInfo?.location ?? "未知节点"
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
                    return .probabilistic(lastSeen: "昨日", avgInterval: "48~72 小时", probabilityPct: 65, note: "历史周期拟合中")
                }
            ),
            
            WatchCatalogItem(
                id: "reactor",
                category: .treasures,
                title: "奥罗金反应堆 (银土豆)",
                subtitle: "战甲/同伴/载具容量翻倍核心道具",
                icon: "bolt.shield.fill",
                frequencyHint: "入侵/警报约 48~72h 一次",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("Reactor") || r.containsKeyword("反应堆") {
                            let loc = alert.MissionInfo?.location ?? "未知节点"
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
                title: "塑形块 (Forma 蓝图/成品)",
                subtitle: "装备极化改变槽位极性必备",
                icon: "cube.fill",
                frequencyHint: "派系入侵常态轮换，约 24~36h",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Forma") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Forma") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "14小时前", avgInterval: "24~36 小时", probabilityPct: 52, note: "历史正常周期区间")
                }
            ),
            
            WatchCatalogItem(
                id: "exilus_warframe",
                category: .treasures,
                title: "战甲特殊功能槽连接器",
                subtitle: "解锁战甲 Exilus 特殊功能槽位",
                icon: "square.split.diagonal.2x2",
                frequencyHint: "大型入侵争夺战，约 3~5 天",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Exilus") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Exilus") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "3天前", avgInterval: "3~5 天", probabilityPct: 40, note: "历史轮替估算中")
                }
            ),
            
            WatchCatalogItem(
                id: "exilus_weapon",
                category: .treasures,
                title: "武器特殊功能槽连接器",
                subtitle: "解锁武器 Exilus 槽位",
                icon: "wrench.and.screwdriver",
                frequencyHint: "大型入侵争夺战",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("WeaponExilus") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("WeaponExilus") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "4天前", avgInterval: "4~6 天", probabilityPct: 35, note: "随机入侵轮换")
                }
            ),
            
            WatchCatalogItem(
                id: "riven_sliver",
                category: .treasures,
                title: "裂罅碎石 (Riven Sliver)",
                subtitle: "钢铁之路与突击掉落，兑换紫卡与精炼道具",
                icon: "diamond.fill",
                frequencyHint: "突击、警报与钢铁之路 Eximus 掉落",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("RivenSliver") || r.containsKeyword("裂罅碎石") {
                            let loc = alert.MissionInfo?.location ?? "未知节点"
                            let exp = alert.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "限时警报 · \(loc)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "常驻产出", avgInterval: "每日重置", probabilityPct: 90, note: "钢铁之路可常驻获取")
                }
            ),
            
            WatchCatalogItem(
                id: "kavat_code",
                category: .treasures,
                title: "库娃遗传密码",
                subtitle: "孵化笑面猫/镜像猫必备扫描产物",
                icon: "pawprint.fill",
                frequencyHint: "警报突发或火卫二遗迹扫描",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("KavatCode") || r.containsKeyword("库娃") {
                            let loc = alert.MissionInfo?.location ?? "未知节点"
                            let exp = alert.Expiry?.date
                            return .active(location: "限时警报 · \(loc)", expiry: exp, remainingSeconds: exp?.timeIntervalSinceNow ?? 0)
                        }
                    }
                    return .probabilistic(lastSeen: "2天前", avgInterval: "2~3 天", probabilityPct: 45, note: "警报随机轮替")
                }
            ),
            
            WatchCatalogItem(
                id: "orokin_cell",
                category: .treasures,
                title: "奥罗金电池 (Orokin Cell)",
                subtitle: "武器与战甲铸造高消耗稀有材料",
                icon: "battery.100.bolt",
                frequencyHint: "警报突发 / 土星谷神星常驻",
                evaluate: { ws in
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward,
                           r.containsKeyword("OrokinCell") || r.containsKeyword("奥罗金电池") {
                            let loc = alert.MissionInfo?.location ?? "未知节点"
                            let exp = alert.Expiry?.date
                            return .active(location: "限时警报 · \(loc)", expiry: exp, remainingSeconds: exp?.timeIntervalSinceNow ?? 0)
                        }
                    }
                    return .probabilistic(lastSeen: "警报随机", avgInterval: "24~48 小时", probabilityPct: 60, note: "常驻土星海王星掉落")
                }
            ),
            
            // ==================== 2. 周期与重置 (100% 确定性) ====================
            WatchCatalogItem(
                id: "cetus_night",
                category: .cycles,
                title: "夜灵平野 · 入夜 (三傻捕猎)",
                subtitle: "兆力使 / 巨力使 / 水力使 捕捞狂热期",
                icon: "moon.stars.fill",
                frequencyHint: "严格 150 分钟循环 (100m 白昼 / 50m 黑夜)",
                evaluate: { ws in
                    for s in ws.SyndicateMissions ?? [] where s.Tag == "CetusSyndicate" {
                        if let exp = s.Expiry?.date {
                            let rem = exp.timeIntervalSinceNow
                            if rem <= 3000 && rem > 0 {
                                return .active(location: "黑夜进行中 (剩余 \(Int(rem/60)) 分钟)", expiry: exp, remainingSeconds: rem)
                            } else if rem > 3000 {
                                let nightStart = exp.addingTimeInterval(-3000)
                                let untilNight = nightStart.timeIntervalSinceNow
                                return .deterministic(nextDate: nightStart, timeRemaining: max(0, untilNight), note: "白昼中，距离下次入夜")
                            }
                        }
                    }
                    return .deterministic(nextDate: Date().addingTimeInterval(3600), timeRemaining: 3600, note: "周期倒计时计算中")
                }
            ),
            
            WatchCatalogItem(
                id: "cetus_day",
                category: .cycles,
                title: "夜灵平野 · 白昼",
                subtitle: "希图斯集团赏金与常态采矿捕鱼",
                icon: "sun.max.fill",
                frequencyHint: "严格 150 分钟循环 (100m 白昼)",
                evaluate: { ws in
                    for s in ws.SyndicateMissions ?? [] where s.Tag == "CetusSyndicate" {
                        if let exp = s.Expiry?.date {
                            let rem = exp.timeIntervalSinceNow
                            if rem > 3000 {
                                return .active(location: "白昼进行中 (剩余 \(Int((rem-3000)/60)) 分钟)", expiry: exp.addingTimeInterval(-3000), remainingSeconds: rem - 3000)
                            } else if rem > 0 {
                                return .deterministic(nextDate: exp, timeRemaining: rem, note: "黑夜中，距离下次天亮")
                            }
                        }
                    }
                    return .deterministic(nextDate: Date().addingTimeInterval(1800), timeRemaining: 1800, note: "平原白昼倒计时")
                }
            ),
            
            WatchCatalogItem(
                id: "vallis_warm",
                category: .cycles,
                title: "奥布山谷 · 暖温期",
                subtitle: "福尔图娜稀有机械鱼群浮现期",
                icon: "thermometer.sun.fill",
                frequencyHint: "严格 26分40秒 循环 (暖温 400s / 寒冷 1200s)",
                evaluate: { ws in
                    // Vallis 1600s cycle: base epoch reference
                    let epoch: Double = 1542067200
                    let now = Date().timeIntervalSince1970
                    let cycle = (now - epoch).truncatingRemainder(dividingBy: 1600)
                    if cycle < 400 {
                        let rem = 400 - cycle
                        let exp = Date().addingTimeInterval(rem)
                        return .active(location: "暖温期进行中 (剩余 \(Int(rem/60)) 分钟)", expiry: exp, remainingSeconds: rem)
                    } else {
                        let untilWarm = 1600 - cycle
                        let nextDate = Date().addingTimeInterval(untilWarm)
                        return .deterministic(nextDate: nextDate, timeRemaining: untilWarm, note: "寒冷期中，距离下次暖温")
                    }
                }
            ),
            
            WatchCatalogItem(
                id: "baro_trader",
                category: .cycles,
                title: "虚空商人 Baro Ki'Teer",
                subtitle: "隔周周五到港，带来专属 Prime MOD 与饰品",
                icon: "person.crop.rectangle.stack",
                frequencyHint: "隔周周五 21:00 到港，停留 48 小时",
                evaluate: { ws in
                    if let baro = ws.VoidTraders?.first {
                        if baro.isActive {
                            let exp = baro.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            return .active(location: "已到港 · 位于 \(baro.Node)", expiry: exp, remainingSeconds: rem)
                        } else if let act = baro.Activation?.date {
                            let rem = act.timeIntervalSinceNow
                            return .deterministic(nextDate: act, timeRemaining: max(0, rem), note: "虚空航行中，距离下次到港")
                        }
                    }
                    return .deterministic(nextDate: Date().addingTimeInterval(86400 * 7), timeRemaining: 86400 * 7, note: "隔周五准时到港")
                }
            ),
            
            WatchCatalogItem(
                id: "sortie_daily_reset",
                category: .cycles,
                title: "每日突击重置",
                subtitle: "北京时间 00:00 准时刷新",
                icon: "shield.checkered",
                frequencyHint: "每日固定时间刷新",
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
                subtitle: "每周一 00:00 刷新，必得执政官源力石",
                icon: "flame.fill",
                frequencyHint: "每周一次源力石产出",
                evaluate: { ws in
                    if let a = ws.LiteSorties?.first, let exp = a.Expiry?.date {
                        return .deterministic(nextDate: exp, timeRemaining: max(0, exp.timeIntervalSinceNow), note: "距离本周执政官结算")
                    }
                    let cal = Calendar.current
                    let now = Date()
                    var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                    comps.weekday = 2
                    comps.hour = 0
                    comps.minute = 0
                    comps.second = 0
                    var nextMonday = cal.date(from: comps) ?? now.addingTimeInterval(86400 * 3)
                    if nextMonday <= now {
                        nextMonday = cal.date(byAdding: .day, value: 7, to: nextMonday) ?? now.addingTimeInterval(86400 * 7)
                    }
                    return .deterministic(nextDate: nextMonday, timeRemaining: max(0, nextMonday.timeIntervalSince(now)), note: "每周一 00:00 准时刷新")
                }
            ),
            
            // ==================== 3. 效率裂隙 (开核桃速度首选) ====================
            WatchCatalogItem(
                id: "fissure_t1_speed",
                category: .speedrun,
                title: "古纪 (Lith) 捕获 / 歼灭",
                subtitle: "1 分钟速开古纪遗物",
                icon: "hare.fill",
                frequencyHint: "全天随机轮替，空窗通常 < 40m",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT1" {
                        if f.MissionType == "MT_CAPTURE" || f.MissionType == "MT_EXTERMINATION" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_CAPTURE" ? "捕获" : "歼灭"
                            return .active(location: "\(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "20 分钟前", avgInterval: "35 分钟", probabilityPct: 82, note: "空窗期极短，即将轮替刷新")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_t2_speed",
                category: .speedrun,
                title: "前纪 (Meso) 捕获 / 歼灭",
                subtitle: "前纪遗物快速开包",
                icon: "hare.fill",
                frequencyHint: "全天随机轮替",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT2" {
                        if f.MissionType == "MT_CAPTURE" || f.MissionType == "MT_EXTERMINATION" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_CAPTURE" ? "捕获" : "歼灭"
                            return .active(location: "\(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "15 分钟前", avgInterval: "35 分钟", probabilityPct: 75, note: "轮替周期拟合中")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_t3_speed",
                category: .speedrun,
                title: "中纪 (Neo) 捕获 / 歼灭",
                subtitle: "中纪遗物快速开包",
                icon: "hare.fill",
                frequencyHint: "全天随机轮替",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT3" {
                        if f.MissionType == "MT_CAPTURE" || f.MissionType == "MT_EXTERMINATION" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_CAPTURE" ? "捕获" : "歼灭"
                            return .active(location: "\(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "30 分钟前", avgInterval: "40 分钟", probabilityPct: 68, note: "即将进入下一轮组")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_t4_speed",
                category: .speedrun,
                title: "后纪 (Axi) 捕获 / 歼灭",
                subtitle: "后纪核心高价值遗物速开",
                icon: "hare.fill",
                frequencyHint: "全天随机轮替",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT4" {
                        if f.MissionType == "MT_CAPTURE" || f.MissionType == "MT_EXTERMINATION" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_CAPTURE" ? "捕获" : "歼灭"
                            return .active(location: "\(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "25 分钟前", avgInterval: "45 分钟", probabilityPct: 70, note: "后纪高频轮换")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_omnia",
                category: .speedrun,
                title: "全能裂隙 (Omnia)",
                subtitle: "火卫二实验室与扎里曼，支持任意纪元遗物",
                icon: "circle.grid.cross.fill",
                frequencyHint: "火卫二实验室常态轮换",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.Modifier == "VoidT6" || f.Modifier == "Omnia" {
                        let exp = f.Expiry?.date
                        let rem = exp?.timeIntervalSinceNow ?? 0
                        return .active(location: "全能裂隙 · \(f.Node)", expiry: exp, remainingSeconds: rem)
                    }
                    return .probabilistic(lastSeen: "40 分钟前", avgInterval: "60 分钟", probabilityPct: 60, note: "全能节点轮替中")
                }
            ),
            
            WatchCatalogItem(
                id: "fissure_sp_endless",
                category: .speedrun,
                title: "钢铁之路 裂隙 (生存/防御/拦截)",
                subtitle: "钢铁精华、裂隙精炼与资源翻倍核心渠道",
                icon: "shield.slash.fill",
                frequencyHint: "常驻多个无尽任务节点",
                evaluate: { ws in
                    for f in ws.ActiveMissions ?? [] where f.isSteelPath {
                        if f.MissionType == "MT_SURVIVAL" || f.MissionType == "MT_DEFENSE" || f.MissionType == "MT_TERRITORY" {
                            let exp = f.Expiry?.date
                            let rem = exp?.timeIntervalSinceNow ?? 0
                            let type = f.MissionType == "MT_SURVIVAL" ? "生存" : (f.MissionType == "MT_DEFENSE" ? "防御" : "拦截")
                            return .active(location: "钢铁 \(type) · \(f.Node)", expiry: exp, remainingSeconds: rem)
                        }
                    }
                    return .probabilistic(lastSeen: "常驻刷新", avgInterval: "60 分钟", probabilityPct: 95, note: "多点常驻")
                }
            ),
            
            // ==================== 4. 入侵战备与武器部件 ====================
            WatchCatalogItem(
                id: "invasion_mutagen",
                category: .invasions,
                title: "突变原聚合物 (Mutagen Mass)",
                subtitle: "道场生化实验室蓝图研发必备 (3x)",
                icon: "testtube.2",
                frequencyHint: "Infested 派系入侵争夺",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Mutagen") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Mutagen") ?? false) {
                            return .active(location: "派系入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "8 小时前", avgInterval: "18 小时", probabilityPct: 65, note: "道场材料高频入侵")
                }
            ),
            
            WatchCatalogItem(
                id: "invasion_fieldron",
                category: .invasions,
                title: "电磁力导管 (Fieldron)",
                subtitle: "Corpus 阵营高阶装备研发必备 (3x)",
                icon: "bolt.shield",
                frequencyHint: "Grineer vs Corpus 阵营入侵",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Fieldron") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Fieldron") ?? false) {
                            return .active(location: "阵营争夺 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "常态进行", avgInterval: "12 小时", probabilityPct: 85, note: "常驻轮换中")
                }
            ),
            
            WatchCatalogItem(
                id: "invasion_detonite",
                category: .invasions,
                title: "爆燃喷射器 (Detonite Injector)",
                subtitle: "Grineer 化学实验室研发必备 (3x)",
                icon: "flame",
                frequencyHint: "Corpus vs Grineer 阵营入侵",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Detonite") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Detonite") ?? false) {
                            return .active(location: "阵营争夺 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "常态进行", avgInterval: "12 小时", probabilityPct: 85, note: "常驻轮换中")
                }
            ),
            
            WatchCatalogItem(
                id: "invasion_wraith_vandal",
                category: .invasions,
                title: "亡魂 / 破坏者 武器部件",
                subtitle: "卡拉卡·亡魂、德特昂·破坏者、斯特朗·亡魂等部件",
                icon: "wrench.and.screwdriver.fill",
                frequencyHint: "阵营争夺不定期轮替",
                evaluate: { ws in
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        if (inv.AttackerReward?.containsKeyword("Wraith") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Wraith") ?? false) ||
                           (inv.AttackerReward?.containsKeyword("Vandal") ?? false) ||
                           (inv.DefenderReward?.containsKeyword("Vandal") ?? false) {
                            return .active(location: "武器部件入侵 · \(inv.Node)", expiry: nil, remainingSeconds: 0)
                        }
                    }
                    return .probabilistic(lastSeen: "昨天", avgInterval: "2~3 天", probabilityPct: 45, note: "阵营战备不定期轮替")
                }
            ),
            
            // ==================== 5. 特惠与活动 ====================
            WatchCatalogItem(
                id: "global_buffs",
                category: .specials,
                title: "全服加成活动 (双倍经验/资源/现金)",
                subtitle: "全服倍率生效中",
                icon: "bolt.fill",
                frequencyHint: "官方直播、版本更新与节庆活动突发",
                evaluate: { ws in
                    if let buff = ws.GlobalUpgrades?.first {
                        let exp = buff.ExpiryDate?.date
                        let rem = exp?.timeIntervalSinceNow ?? 0
                        return .active(location: "\(Int(buff.Value))× 全服生效中", expiry: exp, remainingSeconds: rem)
                    }
                    return .probabilistic(lastSeen: "重大活动/版本", avgInterval: "突发加成", probabilityPct: 15, note: "官方直播与节庆期间开启")
                }
            ),
            
            WatchCatalogItem(
                id: "darvo_super_deal",
                category: .specials,
                title: "达尔沃特惠 (>50% 折扣)",
                subtitle: "中继站 Darvo 每日特惠半价以上商品",
                icon: "tag.fill",
                frequencyHint: "每日 0:00 刷新进货",
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
                    return .probabilistic(lastSeen: "每日进货", avgInterval: "24 小时", probabilityPct: 30, note: "高折扣随机概率")
                }
            )
        ]
    }
}
