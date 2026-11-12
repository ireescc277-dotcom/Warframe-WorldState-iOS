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
    /// 这里做一次归一化。子派系仍保留其母派系的 canonical key，以便通用的
    /// Grineer / Corpus / Infested faction mod 继续命中；但弱点表单独使用已公布矩阵。
    public static func resolve(rawFaction: String) -> FactionProfile {
        let key = rawFaction.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")

        if key.contains("kuvagrineer") { return kuvaGrineer }
        if key.contains("amalgam") { return corpusAmalgam }
        if key.contains("deimos") { return deimosInfested }
        if key.contains("anarch") { return anarchs }
        if key.contains("techrot") { return techrot }
        if key.contains("scaldra") { return scaldra }
        if key.contains("grineer") { return grineer }
        if key.contains("corpus") { return corpus }
        if key.contains("infest") { return infested }
        if key.contains("orokin") || key.contains("corrupt") { return orokin }
        if key.contains("sentient") { return sentient }
        if key.contains("narmer") { return narmer }
        if key.contains("zariman") { return zariman }
        if key.contains("murmur") { return murmur }
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
    /// Update 36/38 后的公开子派系矩阵。前三项沿用母派系 canonical key，
    /// 使普通的 Bane of Grineer/Corpus/Infested 正确匹配子派系。
    public static let kuvaGrineer = FactionProfile(canonical: "Grineer",
                                                   vulnerable: [.impact, .corrosive], resistant: [.heat])
    public static let corpusAmalgam = FactionProfile(canonical: "Corpus",
                                                     vulnerable: [.electricity, .magnetic], resistant: [.blast])
    public static let deimosInfested = FactionProfile(canonical: "Infested",
                                                      vulnerable: [.blast, .gas], resistant: [.viral])
    public static let anarchs = FactionProfile(canonical: "Anarchs",
                                               vulnerable: [.impact, .electricity], resistant: [.radiation])
    public static let techrot = FactionProfile(canonical: "Techrot",
                                               vulnerable: [.gas, .magnetic], resistant: [.cold])
    public static let scaldra = FactionProfile(canonical: "Scaldra",
                                               vulnerable: [.impact, .corrosive], resistant: [.gas])

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
        faction = FactionProfile.resolve(rawFaction: enemy.faction)
        var notes: [String] = []

        // `showEnemy` in the checked-in warframe-damage source clamps the typed
        // level to the source-data base level before it evaluates a target.
        // Steel Path does not add 100 here: its website branch changes the base
        // health/shields before the level curve is evaluated.
        let effectiveLevel = max(level, enemy.baseLevel)
        self.level = effectiveLevel
        let q = max(0, effectiveLevel - enemy.baseLevel)
        // Direct translation of `showEnemy` + `correctEnemyLvl` in the checked-
        // in website source.  It intentionally uses Double, matching JavaScript
        // Number, rather than the Float-based game/Wiki curve used previously.
        let siteBaseMultiplier = options.steelPath ? 2.5 : 1.0
        let siteBaseHealth = siteBaseMultiplier * floor(enemy.health)
        let siteBaseShield = siteBaseMultiplier * floor(enemy.shield)
        let siteBaseArmor = floor(enemy.armor)
        let normal = EnemyProfile.websiteNormalMultipliers(
            faction: enemy.faction,
            level: effectiveLevel,
            baseLevel: enemy.baseLevel
        )

        var h: Double
        var s: Double
        var a: Double
        let overguardBase: Double
        if enemy.overguard > 0 {
            overguardBase = enemy.overguard
        } else if options.eximus && !enemy.eximusDisabled {
            overguardBase = 12
        } else {
            overguardBase = 0
        }

        if options.eximus && !enemy.eximusDisabled {
            // Website branch: Eximus has complete independent health, shield,
            // and armor multipliers.  It does not feed a changed base back
            // through the normal faction curve.
            h = EnemyProfile.websiteRound(siteBaseHealth
                * EnemyProfile.websiteEximusHealthMultiplier(level: effectiveLevel,
                                                              baseLevel: enemy.baseLevel))
            s = EnemyProfile.websiteRound(siteBaseShield
                * EnemyProfile.websiteEximusShieldMultiplier(level: effectiveLevel,
                                                              baseLevel: enemy.baseLevel))
            a = EnemyProfile.websiteRound(siteBaseArmor
                * EnemyProfile.websiteEximusArmorMultiplier(level: effectiveLevel,
                                                             baseLevel: enemy.baseLevel))
            notes.append("卓越者目标值：使用 warframe-damage 的独立生命、护盾、护甲分支")
        } else {
            h = EnemyProfile.websiteNormalDisplayRound(siteBaseHealth * normal.health)
            s = EnemyProfile.websiteNormalDisplayRound(siteBaseShield * normal.shield)
            a = EnemyProfile.websiteNormalDisplayRound(siteBaseArmor * normal.armor)
        }

        // `showPartyCount` is an explicit site-data capability, not a global
        // damage option.  The website applies its 1/1.5/2/3 table to health
        // only (after normal or Eximus health scaling); shields, armor, and
        // Overguard are deliberately unchanged.
        let partyHealthMultiplier = enemy.showPartyCount
            ? EnemyProfile.partyHealthMultiplier(squadSize: options.squadSize)
            : 1
        if enemy.showPartyCount {
            h *= partyHealthMultiplier
        }

        // Website order is whole-number rounding, then [200, 2700] clamping;
        // zero armor stays zero. Dynamic removal still happens in the simulator.
        if a > Rules.armorClampMax {
            a = Rules.armorClampMax
        } else if a > 0 && a <= Rules.armorClampMin {
            a = Rules.armorClampMin
        }
        let og = EnemyProfile.websiteOverguard(base: overguardBase,
                                                level: effectiveLevel,
                                                baseLevel: enemy.baseLevel)

        health = h
        shield = s
        armor = a
        overguard = og
        armorDR = Rules.enemyArmorDR(netArmor: a)

        if q > 0 && a >= Rules.armorClampMax {
            notes.append("护甲已顶到 2700 上限（90% 减伤）")
        }
        if overguardBase > 0 {
            notes.append("超宏：使用 warframe-damage 的敌人基础等级分段")
        }
        if enemy.showPartyCount && options.squadSize > 1 {
            let shownMultiplier = partyHealthMultiplier.rounded() == partyHealthMultiplier
                ? String(Int(partyHealthMultiplier))
                : String(partyHealthMultiplier)
            notes.append("小队人数 \(min(max(options.squadSize, 1), 4))：仅生命 ×\(shownMultiplier)")
        }
        notes.append("目标等级曲线：warframe-damage（已检入网站代码）")
        self.notes = notes
    }

    /// Website `healthPartyMult`: 1/1.5/2/3 for 1...4 players.  Kept next
    /// to enemy scaling so the UI supplies only an integer selection and no
    /// formula is embedded in an input adapter.
    static func partyHealthMultiplier(squadSize: Int) -> Double {
        switch min(max(squadSize, 1), 4) {
        case 2: return 1.5
        case 3: return 2
        case 4: return 3
        default: return 1
        }
    }

    // MARK: - Direct warframe-damage target translation

    private struct WebsiteTargetMultipliers {
        let health: Double
        let shield: Double
        let armor: Double
    }

    /// Exact `trans(70, 80, level, baseLevel)` from the checked-in website.
    private static func websiteTransition(level: Int, baseLevel: Int) -> Double {
        let q = Double(max(0, level - baseLevel))
        if q < 70 { return 0 }
        if q > 80 { return 1 }
        let x = (q - 70) / 10
        return 3 * pow(x, 2) - 2 * pow(x, 3)
    }

    /// Direct translation of `correctEnemyLvl`'s normal-enemy curves. Do not
    /// normalize `faction`: the website switches on the raw source-data value.
    private static func websiteNormalMultipliers(faction: String,
                                                 level: Int,
                                                 baseLevel: Int) -> WebsiteTargetMultipliers {
        let q = Double(max(0, level - baseLevel))
        var shieldEarly = 1 + 0.02 * pow(q, 1.75)
        var healthEarly = 1 + 0.015 * pow(q, 2)
        let armorEarly = 1 + 0.005 * pow(q, 1.75)
        var shieldLate = 1 + 1.6 * pow(q, 0.75)
        var healthLate = 1 + 24 * sqrt(q) * sqrt(5) / 5
        let armorLate = 1 + 0.4 * pow(q, 0.75)

        switch faction {
        case "Infested Deimos", "Infested":
            healthEarly = 1 + 0.0225 * pow(q, 2.12)
            healthLate = 1 + 36 * pow(q, 0.72) * sqrt(5) / 5
        case "Corpus":
            healthEarly = 1 + 0.015 * pow(q, 2.12)
            healthLate = 1 + 30 * pow(q, 0.55) * sqrt(5) / 5
            shieldEarly = 1 + 0.02 * pow(q, 1.76)
            shieldLate = 1 + 2 * pow(q, 0.76)
        case "Kuva Grineer", "Grineer":
            healthEarly = 1 + 0.015 * pow(q, 2.12)
            healthLate = 1 + 24 * pow(q, 0.72) * sqrt(5) / 5
        case "Orokin":
            healthEarly = 1 + 0.015 * pow(q, 2.1)
            healthLate = 1 + 24 * pow(q, 0.685) * sqrt(5) / 5
            shieldEarly = 1 + 0.02 * pow(q, 1.75)
            shieldLate = 1 + 2 * pow(q, 0.75)
        case "Techrot":
            healthEarly = 1 + 0.015 * pow(q, 2.1)
            healthLate = 1 + 30.5 * pow(q, 0.72) * sqrt(5) / 5
            shieldEarly = 1 + 0.02 * pow(q, 1.76)
            shieldLate = 1 + 3.4106 * pow(q, 0.76)
        case "Sentient", "Neutral", "Murmur":
            shieldEarly = 1 + 0.02 * pow(q, 1.75)
            shieldLate = 1 + 2 * pow(q, 0.75)
        default:
            break
        }

        let transition = websiteTransition(level: level, baseLevel: baseLevel)
        return WebsiteTargetMultipliers(
            health: healthEarly * (1 - transition) + healthLate * transition,
            shield: shieldEarly * (1 - transition) + shieldLate * transition,
            armor: armorEarly * (1 - transition) + armorLate * transition
        )
    }

    /// Direct translations of `enemyEximusHealth`, `enemyEximusShields`, and
    /// `enemyEximusArmor`. Their bands test the absolute displayed level, as
    /// the source does; only their power terms use (level - baseLevel).
    static func websiteEximusHealthMultiplier(level: Int, baseLevel: Int) -> Double {
        let q = Double(max(0, level - baseLevel))
        let early = 1 + 0.015 * pow(q, 2)
        let late = 1 + 24 * sqrt(5) / 5 * pow(q, 0.5)
        let displayed = Double(level)
        if displayed <= 15 { return early }
        if displayed <= 25 { return (1 + 0.025 * (displayed - 15)) * early }
        if displayed <= 35 { return (1.25 + 0.125 * (displayed - 25)) * early }
        if displayed <= 50 { return (2.5 + 2.0 / 15.0 * (displayed - 35)) * early }
        if displayed <= 100 {
            let t = websiteTransition(level: level, baseLevel: baseLevel)
            return (4.5 + 0.03 * (displayed - 50)) * (early * (1 - t) + late * t)
        }
        return 6 * late
    }

    static func websiteEximusShieldMultiplier(level: Int, baseLevel: Int) -> Double {
        let q = Double(max(0, level - baseLevel))
        let early = 1 + 0.02 * pow(q, 1.75)
        let late = 1 + 2 * pow(q, 0.75)
        let displayed = Double(level)
        if displayed <= 15 { return early }
        if displayed <= 25 { return (1 + 0.025 * (displayed - 15)) * early }
        if displayed <= 35 { return (1.25 + 0.125 * (displayed - 25)) * early }
        if displayed <= 50 { return (2.5 + 2.0 / 15.0 * (displayed - 35)) * early }
        if displayed <= 100 {
            let t = websiteTransition(level: level, baseLevel: baseLevel)
            return (4.5 + 0.03 * (displayed - 50)) * (early * (1 - t) + late * t)
        }
        return 6 * late
    }

    static func websiteEximusArmorMultiplier(level: Int, baseLevel: Int) -> Double {
        let q = Double(max(0, level - baseLevel))
        let early = 1 + 0.005 * pow(q, 1.75)
        let late = 1 + 0.4 * pow(q, 0.75)
        let displayed = Double(level)
        if displayed <= 25 { return early }
        if displayed <= 35 { return (1 + 0.0125 * (displayed - 25)) * early }
        if displayed <= 50 { return (1.125 + 0.06667 * (displayed - 35)) * early }
        if displayed <= 100 {
            let t = websiteTransition(level: level, baseLevel: baseLevel)
            return (1.375 + 0.005 * (displayed - 50)) * (early * (1 - t) + late * t)
        }
        return 1.625 * late
    }

    /// Direct `getEnemyOverguard`. In the website code the q=45...50 region
    /// returns the late expression directly; once q>50, its `eOGTrans` returns
    /// 1 before interpolation, so the same late expression remains in force.
    static func websiteOverguard(base: Double, level: Int, baseLevel: Int) -> Double {
        guard base > 0 else { return 0 }
        let q = Double(max(0, level - baseLevel))
        let early = 1 + 0.0015 * pow(q, 4)
        let late = 1 + 260 * pow(q, 0.9)
        return (q < 45 ? early : late) * base
    }

    /// JavaScript `Math.round` for non-negative target stats.
    private static func websiteRound(_ value: Double) -> Double {
        value.rounded(.toNearestOrAwayFromZero)
    }

    /// Website normal-target branch retains two decimal places before its
    /// display integer. The Eximus branch performs only the latter round.
    private static func websiteNormalDisplayRound(_ value: Double) -> Double {
        websiteRound(websiteRound(value * 100) / 100)
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

    /// Some targets (for example Archons) expose a separate status-damage
    /// reduction in the same data block; it applies to the DoT event, not to
    /// the direct hit that produced the proc.
    public var statusDR: Double {
        min(max(enemy.innateDR["status"] ?? 0, 0), 1)
    }

    /// 数据里的 `elemRes` 是减伤比例，而不是剩余伤害倍率。
    public func elementalResistance(_ type: DamageType) -> Double {
        max(0, 1 - (enemy.elemRes[type.rawValue] ?? 0))
    }

    public var stats: EnemyStats {
        EnemyStats(health: health, armor: armor, shield: shield, overguard: overguard, armorDR: armorDR)
    }
}
