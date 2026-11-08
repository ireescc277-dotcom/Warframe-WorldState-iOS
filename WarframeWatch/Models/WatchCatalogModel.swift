import Foundation

public enum CatalogSection: String, CaseIterable, Identifiable {
    case all = "全部"
    case items = "物资与奖励"
    case fissures = "裂隙规则"
    case cycles = "周期与重置"
    case nodes = "星图节点"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .items: return "sparkles"
        case .fissures: return "bolt.badge.clock"
        case .cycles: return "clock.arrow.circlepath"
        case .nodes: return "globe.asia.australia.fill"
        }
    }
}

public enum TargetLiveStatus {
    case active(summary: String, location: String, expiry: Date?, remainingSeconds: TimeInterval)
    case deterministic(nextDate: Date, timeRemaining: TimeInterval, note: String)
    case idle(hint: String)
    
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
    
    public var sortOrder: Int {
        switch self {
        case .active: return 0
        case .deterministic: return 1
        case .idle: return 2
        }
    }
}

public struct ExhaustiveWatchEntry: Identifiable {
    public let id: String
    public let section: CatalogSection
    public let title: String
    public let subtitle: String
    public let icon: String
    public let evaluate: (WorldState) -> TargetLiveStatus
    
    public init(
        id: String,
        section: CatalogSection,
        title: String,
        subtitle: String,
        icon: String,
        evaluate: @escaping (WorldState) -> TargetLiveStatus
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.evaluate = evaluate
    }
}

public struct EvaluatedWatchEntry: Identifiable {
    public var id: String { entry.id }
    public let entry: ExhaustiveWatchEntry
    public let status: TargetLiveStatus
    public let isSubscribed: Bool
}

public final class ExhaustiveCatalogRepository {
    public static let shared = ExhaustiveCatalogRepository()
    
    public private(set) var allEntries: [ExhaustiveWatchEntry] = []
    
    private init() {
        buildCatalog()
    }
    
    private func buildCatalog() {
        var list: [ExhaustiveWatchEntry] = []
        
        // ==================== 1. 周期与重置 (确定性未来) ====================
        list.append(ExhaustiveWatchEntry(
            id: "cycle_cetus_night",
            section: .cycles,
            title: "夜灵平野 · 黑夜 (三傻猎杀)",
            subtitle: "兆力使/巨力使/水力使 50分钟猎杀期",
            icon: "moon.stars.fill",
            evaluate: { ws in
                for s in ws.SyndicateMissions ?? [] where s.Tag == "CetusSyndicate" {
                    if let exp = s.Expiry?.date {
                        let rem = exp.timeIntervalSinceNow
                        if rem <= 3000 && rem > 0 {
                            return .active(summary: "黑夜进行中", location: "夜灵平野", expiry: exp, remainingSeconds: rem)
                        } else if rem > 3000 {
                            let nightStart = exp.addingTimeInterval(-3000)
                            return .deterministic(nextDate: nightStart, timeRemaining: nightStart.timeIntervalSinceNow, note: "距离下次入夜")
                        }
                    }
                }
                return .idle(hint: "150分钟循环")
            }
        ))
        
        list.append(ExhaustiveWatchEntry(
            id: "cycle_cetus_day",
            section: .cycles,
            title: "夜灵平野 · 白昼",
            subtitle: "希图斯赏金与平原采矿捕鱼",
            icon: "sun.max.fill",
            evaluate: { ws in
                for s in ws.SyndicateMissions ?? [] where s.Tag == "CetusSyndicate" {
                    if let exp = s.Expiry?.date {
                        let rem = exp.timeIntervalSinceNow
                        if rem > 3000 {
                            let dayEnd = exp.addingTimeInterval(-3000)
                            return .active(summary: "白昼进行中", location: "夜灵平野", expiry: dayEnd, remainingSeconds: rem - 3000)
                        } else if rem > 0 {
                            return .deterministic(nextDate: exp, timeRemaining: rem, note: "距离下次天亮")
                        }
                    }
                }
                return .idle(hint: "150分钟循环")
            }
        ))
        
        list.append(ExhaustiveWatchEntry(
            id: "cycle_vallis_warm",
            section: .cycles,
            title: "奥布山谷 · 暖温期",
            subtitle: "稀有机械鱼群浮现期 (400秒)",
            icon: "thermometer.sun.fill",
            evaluate: { _ in
                let epoch: Double = 1542067200
                let now = Date().timeIntervalSince1970
                let cycle = (now - epoch).truncatingRemainder(dividingBy: 1600)
                if cycle < 400 {
                    let rem = 400 - cycle
                    return .active(summary: "暖温期进行中", location: "奥布山谷", expiry: Date().addingTimeInterval(rem), remainingSeconds: rem)
                } else {
                    let untilWarm = 1600 - cycle
                    return .deterministic(nextDate: Date().addingTimeInterval(untilWarm), timeRemaining: untilWarm, note: "距离下次暖温")
                }
            }
        ))
        
        list.append(ExhaustiveWatchEntry(
            id: "cycle_baro",
            section: .cycles,
            title: "虚空商人 Baro Ki'Teer",
            subtitle: "隔周周五 21:00 进港停留 48 小时",
            icon: "person.crop.rectangle.stack",
            evaluate: { ws in
                if let baro = ws.VoidTraders?.first {
                    if baro.isActive {
                        let exp = baro.Expiry?.date
                        return .active(summary: "已进港", location: baro.Node, expiry: exp, remainingSeconds: exp?.timeIntervalSinceNow ?? 0)
                    } else if let act = baro.Activation?.date {
                        return .deterministic(nextDate: act, timeRemaining: max(0, act.timeIntervalSinceNow), note: "距离下次到港")
                    }
                }
                return .idle(hint: "每隔两周进港")
            }
        ))
        
        list.append(ExhaustiveWatchEntry(
            id: "cycle_sortie_reset",
            section: .cycles,
            title: "每日突击任务重置",
            subtitle: "每日北京时间 00:00 准时刷新",
            icon: "shield.checkered",
            evaluate: { ws in
                if let s = ws.Sorties?.first, let exp = s.Expiry?.date {
                    return .deterministic(nextDate: exp, timeRemaining: max(0, exp.timeIntervalSinceNow), note: "距离突击重置")
                }
                return .idle(hint: "每日 00:00")
            }
        ))
        
        list.append(ExhaustiveWatchEntry(
            id: "cycle_archon_reset",
            section: .cycles,
            title: "执政官猎杀每周重置",
            subtitle: "每周一 00:00 刷新，必得执政官源力石",
            icon: "flame.fill",
            evaluate: { ws in
                if let a = ws.LiteSorties?.first, let exp = a.Expiry?.date {
                    return .deterministic(nextDate: exp, timeRemaining: max(0, exp.timeIntervalSinceNow), note: "距离执政官重置")
                }
                return .idle(hint: "每周一 00:00")
            }
        ))
        
        // ==================== 2. 全量物资与奖励穷举 ====================
        let trackedItems: [(id: String, name: String, desc: String, kw: [String])] = [
            ("catalyst", "奥罗金催化剂 (金土豆)", "武器容量翻倍核心道具", ["Catalyst", "催化剂"]),
            ("reactor", "奥罗金反应堆 (银土豆)", "战甲/同伴/载具容量翻倍", ["Reactor", "反应堆"]),
            ("forma", "塑形块 (Forma)", "装备极化槽位极性改变", ["Forma", "塑形块"]),
            ("exilus_wf", "战甲特殊功能槽连接器", "解锁战甲特殊功能槽", ["ExilusAdapter", "Exilus"]),
            ("exilus_wp", "武器特殊功能槽连接器", "解锁武器特殊功能槽", ["WeaponExilus"]),
            ("riven_sliver", "裂罅碎石", "钢铁之路与突击掉落，兑换紫卡", ["RivenSliver", "裂罅碎石"]),
            ("kavat_code", "库娃遗传密码", "制造猫甲与孵化库娃必备", ["KavatCode", "库娃"]),
            ("nitain", "尼坦萃取物", "特殊警报/商城稀有化学萃取物", ["NitainExtract", "尼坦"]),
            ("orokin_cell", "奥罗金电池", "高阶战甲与 Prime 铸造消耗", ["OrokinCell", "奥罗金电池"]),
            ("mutagen_mass", "突变原聚合物 (3x)", "道场生物实验室研发必备", ["Mutagen", "突变原"]),
            ("fieldron", "电磁力导管 (3x)", "道场能源实验室研发必备", ["Fieldron", "电磁力导管"]),
            ("detonite", "爆燃喷射器 (3x)", "道场化学实验室研发必备", ["Detonite", "爆燃喷射器"]),
            ("karak_wraith", "卡拉卡·亡魂 部件/蓝图", "克隆尼阵营亡魂步枪部件", ["KarakWraith"]),
            ("dera_vandal", "德拉·破坏者 部件/蓝图", "科普斯阵营能量步枪部件", ["DeraVandal"]),
            ("strun_wraith", "斯特朗·亡魂 部件/蓝图", "散弹枪亡魂部件", ["StrunWraith"]),
            ("snipetron_vandal", "狙击特隆·破坏者 部件/蓝图", "狙击枪破坏者部件", ["SnipetronVandal"]),
            ("latron_wraith", "拉特隆·亡魂 部件/蓝图", "半自动步枪亡魂部件", ["LatronWraith"]),
            ("twin_vipers_wraith", "双子蝰蛇·亡魂 部件/蓝图", "连射副手亡魂部件", ["TwinVipersWraith"]),
            ("sheev", "希芙 (Sheev) 部件/蓝图", "短剑近战武器部件", ["Sheev"])
        ]
        
        for item in trackedItems {
            list.append(ExhaustiveWatchEntry(
                id: "item_\(item.id)",
                section: .items,
                title: item.name,
                subtitle: item.desc,
                icon: "sparkles",
                evaluate: { ws in
                    // Check Alerts
                    for alert in ws.Alerts ?? [] {
                        if let r = alert.MissionInfo?.missionReward {
                            for kw in item.kw {
                                if r.containsKeyword(kw) {
                                    let loc = alert.MissionInfo?.location ?? "未知节点"
                                    let exp = alert.Expiry?.date
                                    return .active(summary: "限时警报", location: loc, expiry: exp, remainingSeconds: exp?.timeIntervalSinceNow ?? 0)
                                }
                            }
                        }
                    }
                    // Check Invasions
                    for inv in ws.Invasions ?? [] where !inv.Completed {
                        for kw in item.kw {
                            if (inv.AttackerReward?.containsKeyword(kw) ?? false) ||
                               (inv.DefenderReward?.containsKeyword(kw) ?? false) {
                                return .active(summary: "派系入侵", location: inv.Node, expiry: nil, remainingSeconds: 0)
                            }
                        }
                    }
                    return .idle(hint: "未在当前世界状态中出现")
                }
            ))
        }
        
        // ==================== 3. 裂隙规则全组合 (纪元 × 模式 × 难度) ====================
        let eras: [(id: String, name: String)] = [
            ("VoidT1", "古纪"), ("VoidT2", "前纪"), ("VoidT3", "中纪"),
            ("VoidT4", "后纪"), ("VoidT5", "安魂"), ("VoidT6", "全能")
        ]
        
        let fissureModes: [(id: String, name: String)] = [
            ("MT_CAPTURE", "捕获"),
            ("MT_EXTERMINATION", "歼灭"),
            ("MT_SURVIVAL", "生存"),
            ("MT_DEFENSE", "防御"),
            ("MT_DISRUPTION", "中断"),
            ("MT_RESCUE", "救援"),
            ("MT_INTEL", "间谍")
        ]
        
        for era in eras {
            for mode in fissureModes {
                // 普通
                list.append(ExhaustiveWatchEntry(
                    id: "fissure_\(era.id)_\(mode.id)_normal",
                    section: .fissures,
                    title: "\(era.name) · \(mode.name)",
                    subtitle: "普通难度 遗物裂隙",
                    icon: "hare.fill",
                    evaluate: { ws in
                        for f in ws.ActiveMissions ?? [] where f.Modifier == era.id && !f.isSteelPath {
                            if f.MissionType == mode.id {
                                let exp = f.Expiry?.date
                                return .active(summary: "\(era.name) \(mode.name)", location: f.Node, expiry: exp, remainingSeconds: exp?.timeIntervalSinceNow ?? 0)
                            }
                        }
                        return .idle(hint: "随机轮替刷新中")
                    }
                ))
                
                // 钢铁之路
                list.append(ExhaustiveWatchEntry(
                    id: "fissure_\(era.id)_\(mode.id)_hard",
                    section: .fissures,
                    title: "\(era.name) · \(mode.name) (钢铁之路)",
                    subtitle: "钢铁之路 掉落钢铁精华与双倍",
                    icon: "shield.slash.fill",
                    evaluate: { ws in
                        for f in ws.ActiveMissions ?? [] where f.Modifier == era.id && f.isSteelPath {
                            if f.MissionType == mode.id {
                                let exp = f.Expiry?.date
                                return .active(summary: "钢铁 \(era.name) \(mode.name)", location: f.Node, expiry: exp, remainingSeconds: exp?.timeIntervalSinceNow ?? 0)
                            }
                        }
                        return .idle(hint: "钢铁之路轮转中")
                    }
                ))
            }
        }
        
        self.allEntries = list
    }
}
