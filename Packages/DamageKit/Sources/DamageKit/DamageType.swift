import Foundation

/// 伤害类型。
///
/// 命名对齐 `web/app/site/weapons/*.json` 里 `damage` 字典的键（小写）；
/// 数据里偶尔出现的 `fire` 是 `heat` 的别名，`finisher` 单独保留。
///
/// 元素组合表来源：<https://wiki.warframe.com/w/Damage>
///   Heat + Cold = Blast / Heat + Toxin = Gas / Heat + Electricity = Radiation
///   Cold + Toxin = Viral / Cold + Electricity = Magnetic / Toxin + Electricity = Corrosive
public enum DamageType: String, CaseIterable, Codable, Hashable, Sendable {
    // 物理
    case impact
    case puncture
    case slash

    // 主元素（可两两组合）
    case heat
    case cold
    case electricity
    case toxin

    // 副元素（由主元素组合而来，不会再去组合）
    case blast
    case corrosive
    case gas
    case magnetic
    case radiation
    case viral

    // 特殊
    case void
    case tau
    case `true`
    case cinematic
    case finisher

    /// 从数据文件里的键解析；未知键返回 nil，由调用方记诊断而不是静默丢弃。
    public init?(dataKey: String) {
        let k = dataKey.lowercased()
        if k == "fire" { self = .heat; return }
        guard let t = DamageType(rawValue: k) else { return nil }
        self = t
    }

    public var isPhysical: Bool {
        switch self {
        case .impact, .puncture, .slash: return true
        default: return false
        }
    }

    /// 能参与两两组合的主元素。
    public var isPrimaryElement: Bool {
        switch self {
        case .heat, .cold, .electricity, .toxin: return true
        default: return false
        }
    }

    /// 已经是组合结果的副元素。
    public var isSecondaryElement: Bool {
        switch self {
        case .blast, .corrosive, .gas, .magnetic, .radiation, .viral: return true
        default: return false
        }
    }

    public var isElemental: Bool { isPrimaryElement || isSecondaryElement }

    public var zhName: String {
        switch self {
        case .impact: return "冲击"
        case .puncture: return "穿刺"
        case .slash: return "切割"
        case .heat: return "火焰"
        case .cold: return "冰冻"
        case .electricity: return "电击"
        case .toxin: return "毒素"
        case .blast: return "爆炸"
        case .corrosive: return "腐蚀"
        case .gas: return "毒气"
        case .magnetic: return "磁力"
        case .radiation: return "辐射"
        case .viral: return "病毒"
        case .void: return "虚空"
        case .tau: return "Tau"
        case .true: return "真实"
        case .cinematic: return "过场"
        case .finisher: return "处决"
        }
    }

    /// 主元素组合优先级。Wiki 明确 Kuva/Tenet 双固有元素武器按 HCET 排序，
    /// 其余情况按 Mod 槽位顺序；见 `BuildResolver.elementOrder`。
    static let primaryOrder: [DamageType] = [.heat, .cold, .electricity, .toxin]

    /// 两个主元素合成什么；不构成合法组合返回 nil。
    public static func combined(_ a: DamageType, _ b: DamageType) -> DamageType? {
        let pair = Set([a, b])
        guard pair.count == 2 else { return nil }
        if pair == Set([.heat, .cold]) { return .blast }
        if pair == Set([.heat, .toxin]) { return .gas }
        if pair == Set([.heat, .electricity]) { return .radiation }
        if pair == Set([.cold, .toxin]) { return .viral }
        if pair == Set([.cold, .electricity]) { return .magnetic }
        if pair == Set([.toxin, .electricity]) { return .corrosive }
        return nil
    }
}

/// 状态效果的种类。跟伤害类型一一对应，单独列出来是因为
/// 「物理伤害类型」和「能触发 DOT 的类型」不是同一个集合。
public enum ProcKind: String, Codable, Hashable, Sendable, CaseIterable {
    case bleed          // Slash
    case ignite         // Heat
    case poison         // Toxin
    case tesla          // Electricity
    case gasCloud       // Gas
    case detonate      // Blast
    case corrosion      // Corrosive
    case virus          // Viral
    case disrupt        // Magnetic
    case freeze         // Cold
    case weakened       // Puncture
    case knockback      // Impact
    case confusion      // Radiation

    public init?(damageType: DamageType) {
        switch damageType {
        case .slash: self = .bleed
        case .heat: self = .ignite
        case .toxin: self = .poison
        case .electricity: self = .tesla
        case .gas: self = .gasCloud
        case .blast: self = .detonate
        case .corrosive: self = .corrosion
        case .viral: self = .virus
        case .magnetic: self = .disrupt
        case .cold: self = .freeze
        case .puncture: self = .weakened
        case .impact: self = .knockback
        case .radiation: self = .confusion
        default: return nil
        }
    }

    /// 这个 proc 会不会按 tick 持续掉血。
    public var isDamageOverTime: Bool {
        switch self {
        case .bleed, .ignite, .poison, .tesla, .gasCloud: return true
        default: return false
        }
    }
}


extension Dictionary where Key == DamageType, Value == Double {
    /// 固定顺序的键值对。
    ///
    /// Swift 的 Dictionary 迭代顺序取决于哈希种子，直接拿来累加会让
    /// 同一输入在不同进程/不同次调用里出现最后一位的浮点差异。
    /// 全部按 `DamageType.allCases` 的顺序遍历，保证结果逐位可复现。
    public var ordered: [(DamageType, Double)] {
        DamageType.allCases.compactMap { key in
            guard let value = self[key] else { return nil }
            return (key, value)
        }
    }

    /// 顺序确定的求和。
    public var totalDamage: Double {
        ordered.reduce(0) { $0 + $1.1 }
    }
}
