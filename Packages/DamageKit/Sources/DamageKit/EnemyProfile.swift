import Foundation

/// 派系抗性档位。
///
/// Update 36.0 把「按生命/护甲类型算修正」改成了「按派系算」，
/// 只有易伤 ×1.5 / 抗性 ×0.5 两档。
/// 来源：<https://wiki.warframe.com/w/Damage>（"Simplified Faction Resistances"）
public struct FactionProfile: Sendable, Equatable {
    public let canonical: String
    public let vulnerable: Set<DamageType>
    public let resistant: Set<DamageType>

    public init(canonical: String, vulnerable: Set<DamageType>, resistant: Set<DamageType>) {
        self.canonical = canonical
        self.vulnerable = vulnerable
        self.resistant = resistant
    }

    /// 数据里的派系名很脏（`" Infested"`、`"Infestation"`、`"Kuva Grineer"`……），
    /// 这里做一次归一化。
    ///
    /// 子派系（Kuva Grineer / Corpus Amalgam / Deimos Infested）wiki 只说了
    /// "会有不同的弱点抗性" 但没给具体值，这里按母派系处理，见 README 待确认项。
    public static func resolve(rawFaction: String) -> FactionProfile {
        let key = rawFaction.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")

        if key.contains("grineer") { return grineer }
        if key.contains("corpus") { return corpus }
        if key.contains("infest") { return infested }
        if key.contains("orokin") || key.contains("corrupt") || key.contains("anarch") { return orokin }
        if key.contains("sentient") { return sentient }
        if key.contains("narmer") { return narmer }
        if key.contains("zariman") { return zariman }
        if key.contains("murmur") { return murmur }
        if key.contains("techrot") { return techrot }
        if key.contains("scaldra") { return scaldra }
        return neutral
    }

    public static let neutral = FactionProfile(canonical: "Neutral", vulnerable: [], resistant: [])
    public static let grineer = FactionProfile(canonical: "Grineer",
                                               vulnerable: [.impact, .corrosive], resistant: [])
    public static let corpus = FactionProfile(canonical: "Corpus",
                                              vulnerable: [.puncture, .magnetic], resistant: [])
    public static let infested = FactionProfile(canonical: "Infested",
                                                vulnerable: [.slash, .heat], resistant: [])
    public static let orokin = FactionProfile(canonical: "Corrupted",
                                              vulnerable: [.puncture, .viral], resistant: [.radiation])
    public static let sentient = FactionProfile(canonical: "Sentient",
                                                vulnerable: [.cold, .radiation], resistant: [.corrosive])
    public static let narmer = FactionProfile(canonical: "Narmer",
                                              vulnerable: [.slash, .toxin], resistant: [.magnetic])
    public static let zariman = FactionProfile(canonical: "Zariman",
                                               vulnerable: [.void], resistant: [])
    public static let murmur = FactionProfile(canonical: "Murmur",
                                              vulnerable: [.electricity, .radiation], resistant: [.viral])
    /// Techrot / Scaldra 的弱点抗性 wiki 的 Damage 页面没收录（属于 1999 之后的派系），
    /// 先按中性处理，见 README 待确认项。
    public static let techrot = FactionProfile(canonical: "Techrot", vulnerable: [], resistant: [])
    public static let scaldra = FactionProfile(canonical: "Scaldra", vulnerable: [], resistant: [])

    public func multiplier(for type: DamageType) -> Double {
        if vulnerable.contains(type) { return Rules.vulnerableMultiplier }
        if resistant.contains(type) { return Rules.resistantMultiplier }
        return 1
    }
}

/// 敌人按等级缩放后的实际面板。
public struct EnemyProfile: Sendable {
    public let enemy: Enemy
    public let level: Int
    public let faction: FactionProfile
    public let health: Double
    public let armor: Double
    public let shield: Double
    public let overguard: Double
    public let armorDR: Double
    public let notes: [String]

    public init(enemy: Enemy, level: Int, options: Options) {
        self.enemy = enemy
        self.level = level
        faction = FactionProfile.resolve(rawFaction: enemy.faction)
        var notes: [String] = []

        let effectiveLevel = level + (options.steelPath ? Rules.steelPathLevelBonus : 0)
        let q = max(0, effectiveLevel - enemy.baseLevel)
        let spMult = options.steelPath ? Rules.steelPathStatMultiplier : 1.0

        let healthCurve = Rules.healthCurve(faction: faction.canonical)
        let shieldCurve = Rules.shieldCurve(faction: faction.canonical)

        var h = enemy.health * healthCurve.multiplier(level: effectiveLevel, baseLevel: enemy.baseLevel)
        var s = enemy.shield * shieldCurve.multiplier(level: effectiveLevel, baseLevel: enemy.baseLevel)
        var a = enemy.armor * Rules.armorCurve.multiplier(level: effectiveLevel, baseLevel: enemy.baseLevel)
        var og = enemy.overguard * healthCurve.multiplier(level: effectiveLevel, baseLevel: enemy.baseLevel)

        if options.eximus && !enemy.eximusDisabled {
            // 卓越者用独立的生命 / 护盾曲线（wiki Enemy Level Scaling 的 Eximus 分页），
            // 这里按「替换」而不是「叠加」处理，见 README。
            let hasDef = enemy.shield > 0 || enemy.armor > 0
            h = EnemyProfile.eximusHealth(base: enemy.health, level: effectiveLevel, hasShieldOrArmor: hasDef)
            if enemy.shield > 0 {
                s = max(enemy.shield * 1.1, enemy.shield * EnemyProfile.eximusRamp(effectiveLevel))
            }
            notes.append("卓越者：使用独立生命/护盾曲线，护甲未额外提升")
        }

        h *= spMult
        s *= spMult
        og *= spMult

        if a > 0 {
            a = min(max(a, Rules.armorClampMin), Rules.armorClampMax)
        }

        health = h
        shield = s
        armor = a
        overguard = og
        armorDR = Rules.enemyArmorDR(netArmor: a)

        if q > 0 && a >= Rules.armorClampMax {
            notes.append("护甲已顶到 2700 上限（90% 减伤）")
        }
        if enemy.overguard > 0 {
            notes.append("超宏按「生命倍数」解释，见 README 待确认项")
        }
        self.notes = notes
    }

    /// 卓越者生命分段曲线。来源：<https://wiki.warframe.com/w/Enemy_Level_Scaling>（Eximus 页）
    static func eximusRamp(_ x: Int) -> Double {
        let v = Double(x)
        if v <= 15 { return 1.1 }
        if v <= 25 { return 1 + 0.025 * (v - 15) }
        if v <= 35 { return 1.25 + 0.125 * (v - 25) }
        if v <= 50 { return 2.5 + (2.0 / 15.0) * (v - 35) }
        if v <= 100 { return 4.5 + 0.03 * (v - 50) }
        return 6.0
    }

    static func eximusHealth(base: Double, level: Int, hasShieldOrArmor: Bool) -> Double {
        let coef = hasShieldOrArmor ? 0.25 : 0.375
        let scaled = coef * (base + 900) * eximusRamp(level)
        return max(base * 1.1, scaled)
    }

    public func layerHP(_ layer: Layer) -> Double {
        switch layer {
        case .health: return health
        case .armor: return armor
        case .shield: return shield
        case .overguard: return overguard
        }
    }

    /// 敌人在该层上自带的额外减伤（数据里的 innateDR 字段）。
    public func innateDR(_ layer: Layer) -> Double {
        enemy.innateDR[layer.rawValue] ?? 0
    }

    /// 数据里的 elemRes：个别敌人对特定伤害类型有独立倍率。
    public func elementalResistance(_ type: DamageType) -> Double {
        enemy.elemRes[type.rawValue] ?? 1.0
    }

    public var stats: EnemyStats {
        EnemyStats(health: health, armor: armor, shield: shield, overguard: overguard, armorDR: armorDR)
    }
}
