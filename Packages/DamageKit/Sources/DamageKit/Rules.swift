import Foundation

/// 所有游戏数值都集中在这里。
///
/// 设计原则：**逻辑里不出现裸数字**。每个系数都带出处，改数值只需要动这一个文件。
/// 出处优先级：官方 wiki > 官方 patch notes > 游戏数据字段。
///
/// 标了 `TODO(待确认)` 的条目是没能在 wiki 上核到明确表述的，
/// 见 README「待确认项」一节，不要当成已验证结论。
public enum Rules {

    // MARK: - 暴击

    /// 暴击期望倍率。
    ///
    /// 每一档暴击提供 `1 + (CDM - 1)` 的倍率叠加，因此期望值可以写成
    /// `1 + CC × (CDM − 1)`，对 CC > 100% 的橙暴 / 红暴同样成立
    /// （分档只是把同一期望拆成离散值，均值不变）。
    ///
    /// 来源：<https://wiki.warframe.com/w/Critical_Hit>
    ///   "The added Damage is doubled for Big Critical Hits (orange),
    ///    and tripled for Super Critical Hits (red)."
    @inline(__always)
    public static func expectedCritMultiplier(critChance: Double, critDamage: Double) -> Double {
        let cc = max(0, critChance)
        let cdm = max(1, critDamage)
        return 1 + cc * (cdm - 1)
    }

    /// 暴击按 12-bit 量化（wiki "Quantization"）：基础暴伤先 clamp 到 0...32，
    /// 再按 `floor(x × 4095 / 32 + 0.5) × 32 / 4095` 还原。
    /// 只影响基础值，mod 加成在量化之后乘。
    /// 来源：<https://wiki.warframe.com/w/Critical_Hit#Quantization>
    @inline(__always)
    public static func quantizeBaseCritDamage(_ x: Double) -> Double {
        let clamped = min(max(x, 0), 32)
        let code = floor(clamped * 4095.0 / 32.0 + 0.5)
        return code * 32.0 / 4095.0
    }

    // MARK: - 爆头

    /// 默认爆头倍率。wiki 的 Enemy Body Parts 页面按武器类别给出不同倍率，
    /// 这里取最常见的 2.0，并允许 `Options.headshotMultiplier` 覆盖。
    /// 攻击段带 `no_headshot_mult`（AoE）时不生效。
    /// 来源：<https://wiki.warframe.com/w/Enemy_Body_Parts>
    public static let defaultHeadshotMultiplier: Double = 2.0

    // MARK: - 触发与状态

    /// 状态触发的基础持续（秒）。wiki："base duration of 6 seconds"。
    /// 来源：<https://wiki.warframe.com/w/Status_Effect>
    public static let statusBaseDuration: Double = 6.0

    /// tick 间隔（秒）。wiki：每秒一跳。
    public static let statusTickInterval: Double = 1.0

    /// 每跳伤害占「该次命中总伤害」的比例。
    /// 来源：<https://wiki.warframe.com/w/Damage> 与 /w/Status_Effect
    ///   Slash 35%/s，Heat 50%/s，Toxin 50%/s，Electricity 50%/s，Gas 50%/s。
    public static func dotRatio(_ kind: ProcKind) -> Double {
        switch kind {
        case .bleed: return 0.35
        case .ignite, .poison, .tesla, .gasCloud: return 0.50
        default: return 0
        }
    }

    /// 首个 tick 的延迟（秒）。wiki 的 tick 表：
    ///   Slash / Heat / Toxin 在 1s 才跳第一下（0s 那格是空），
    ///   Electricity / Gas 在 0s 立刻跳。
    /// 来源：<https://wiki.warframe.com/w/Status_Effect>
    public static func dotFirstTickDelay(_ kind: ProcKind) -> Double {
        switch kind {
        case .bleed, .ignite, .poison: return 1.0
        case .tesla, .gasCloud: return 0.0
        default: return 0
        }
    }

    /// 持续时间内实际跳几下：延迟 1s 的（1s–6s）跳 6 下；
    /// 无延迟的（0s–5s）也跳 6 下。两者总数相同，只是相位差 1 秒。
    public static func dotTickCount(_ kind: ProcKind) -> Int {
        switch kind {
        case .bleed, .ignite, .poison, .tesla, .gasCloud: return 6
        default: return 0
        }
    }

    /// 会绕过护甲减伤的伤害类型。wiki：Slash 的 Bleed / Cinematic 类型无视 Armor。
    public static func bypassesArmor(_ type: DamageType) -> Bool {
        type == .slash || type == .cinematic || type == .true || type == .finisher
    }

    /// 会绕过护盾的伤害类型。wiki：Toxin "bypasses Shield"。
    public static func bypassesShield(_ type: DamageType) -> Bool { type == .toxin }

    /// Blast 的引信时间（秒）。wiki："inflicting 30% of base damage after 1.5 seconds"。
    /// 来源：<https://wiki.warframe.com/w/Damage/Blast_Damage>
    public static let blastFuse: Double = 1.5
    public static let blastRatio: Double = 0.30

    /// 各状态的叠加上限。wiki 明确给出的：Corrosive 10 / Viral 10 / Magnetic 10 /
    /// Gas 10 / Blast 10；Slash、Heat、Toxin 原文写 "Stacks are not limited"，
    /// 这里给一个足够大的工程上限，避免无限数组。
    public static func maxStacks(_ kind: ProcKind) -> Double {
        switch kind {
        case .corrosion, .virus, .disrupt, .gasCloud, .detonate: return 10
        case .bleed, .ignite, .poison, .tesla: return 100
        default: return 10
        }
    }

    /// Viral：首层 +100%，之后每层 +25%，10 层共 +325%。
    /// 返回对**生命**伤害的乘数（1.0 = 无加成）。
    /// 来源：<https://wiki.warframe.com/w/Damage/Viral_Damage>
    public static func viralMultiplier(stacks: Double) -> Double {
        let n = min(max(stacks, 0), 10)
        if n <= 1 { return 1 + 1.0 * n }
        return 2.0 + 0.25 * (n - 1)
    }

    /// Magnetic：对护盾 / 超宏与 Viral 同构，首层 +100%，每层 +25%。
    /// 来源：<https://wiki.warframe.com/w/Damage/Magnetic_Damage>
    public static func magneticMultiplier(stacks: Double) -> Double {
        viralMultiplier(stacks: stacks)
    }

    /// Corrosive：首层 −26%，之后每层 −6%，10 层共 −80%。
    /// 返回**保留**的护甲比例（1.0 = 没削）。
    /// 来源：<https://wiki.warframe.com/w/Damage/Corrosive_Damage>
    public static func corrosiveArmorFactor(stacks: Double) -> Double {
        let n = min(max(stacks, 0), 10)
        if n <= 0 { return 1 }
        let reduction = n <= 1 ? 0.26 * n : 0.26 + 0.06 * (n - 1)
        return max(0, 1 - reduction)
    }

    /// Heat 状态最多剥 50% 护甲，用 2 秒线性 ramp。
    /// 来源：<https://wiki.warframe.com/w/Damage/Heat_Damage>
    public static let heatArmorStripMax: Double = 0.50
    public static let heatArmorStripRamp: Double = 2.0

    // MARK: - 护甲

    /// 敌人护甲减伤。
    ///
    /// 注意：**不是** `armor/(armor+300)`。wiki 的 Enemy Damage Reduction：
    ///   `DR = 90% × NetArmor / 2700`（NetArmor ≤ 2700）
    ///   `DR = NetArmor / (NetArmor + 300)`（NetArmor > 2700，异常情况）
    /// 来源：<https://wiki.warframe.com/w/Armor#Enemy_Damage_Reduction_Formula>
    public static func enemyArmorDR(netArmor: Double) -> Double {
        let a = max(0, netArmor)
        if a <= 2700 { return 0.90 * a / 2700.0 }
        return a / (a + 300.0)
    }

    /// 等级缩放后的护甲会被夹到 [200, 2700]；初始护甲低于 200 时抬到 200，
    /// 但**后续削甲可以降到 200 以下**。
    /// 来源：同上，"Enemy level scaling normally clamps an enemy's initial armor
    /// to between 200 and 2700. Armor removal can still reduce current armor below 200."
    public static let armorClampMin: Double = 200
    public static let armorClampMax: Double = 2700

    // MARK: - 敌人等级缩放

    /// 敌人等级缩放的两端点曲线：
    ///   `f1(q) = 1 + C1·q^E1`，`f2(q) = 1 + C2·q^E2`，`q = 当前等级 − 基础等级`
    /// 在 q ∈ [70, 80] 之间用 smoothstep 在两条曲线间插值。
    /// 来源：<https://wiki.warframe.com/w/Enemy_Level_Scaling>
    public struct ScalingCurve: Sendable {
        public let c1: Double
        public let e1: Double
        public let c2: Double
        public let e2: Double

        public init(c1: Double, e1: Double, c2: Double, e2: Double) {
            self.c1 = c1
            self.e1 = e1
            self.c2 = c2
            self.e2 = e2
        }

        @inline(__always)
        public func multiplier(level: Int, baseLevel: Int) -> Double {
            let q = Double(max(0, level - baseLevel))
            if q <= 0 { return 1 }
            let f1 = 1 + c1 * pow(q, e1)
            let f2 = 1 + c2 * pow(q, e2)
            let lower = 70.0, upper = 80.0
            if q <= lower { return f1 }
            if q >= upper { return f2 }
            let t = min(max((q - lower) / (upper - lower), 0), 1)
            let s = t * t * (3 - 2 * t)
            return f1 + (f2 - f1) * s
        }
    }

    /// 各阵营的生命曲线。数据里 faction 名字比较脏（有前导空格、
    /// `Infestation` 之类的别名），解析在 `FactionProfile.canonicalFaction` 里做。
    /// 来源：<https://wiki.warframe.com/w/Enemy_Level_Scaling>
    public static func healthCurve(faction: String) -> ScalingCurve {
        switch faction {
        case "Grineer", "Scaldra":
            return ScalingCurve(c1: 0.015, e1: 2.12, c2: 10.7332, e2: 0.72)
        case "Corpus":
            return ScalingCurve(c1: 0.015, e1: 2.12, c2: 13.4165, e2: 0.55)
        case "Infested":
            return ScalingCurve(c1: 0.0225, e1: 2.12, c2: 16.0998, e2: 0.72)
        case "Corrupted", "Anarchs":
            return ScalingCurve(c1: 0.015, e1: 2.1, c2: 10.7332, e2: 0.685)
        case "Techrot":
            return ScalingCurve(c1: 0.02, e1: 2.12, c2: 15.0998, e2: 0.7)
        case "Murmur", "Sentient", "Unaffiliated":
            return ScalingCurve(c1: 0.015, e1: 2.0, c2: 10.7332, e2: 0.5)
        default:
            // 没有对应 tab 的阵营（Stalker / Tenno / 空串等）沿用最保守的一组。
            return ScalingCurve(c1: 0.015, e1: 2.0, c2: 10.7332, e2: 0.5)
        }
    }

    /// 护盾曲线。
    /// 来源：<https://wiki.warframe.com/w/Enemy_Level_Scaling>
    public static func shieldCurve(faction: String) -> ScalingCurve {
        switch faction {
        case "Corpus":
            return ScalingCurve(c1: 0.02, e1: 1.76, c2: 2, e2: 0.76)
        case "Corrupted", "Anarchs":
            return ScalingCurve(c1: 0.02, e1: 1.75, c2: 2, e2: 0.75)
        case "Grineer", "Sentient":
            return ScalingCurve(c1: 0.02, e1: 1.75, c2: 1.6, e2: 0.75)
        case "Techrot":
            return ScalingCurve(c1: 0.02, e1: 1.76, c2: 3.5, e2: 0.76)
        default:
            return ScalingCurve(c1: 0.02, e1: 1.75, c2: 2, e2: 0.75)
        }
    }

    /// 护甲曲线，所有阵营共用一套。
    /// 来源：<https://wiki.warframe.com/w/Enemy_Level_Scaling>
    public static let armorCurve = ScalingCurve(c1: 0.005, e1: 1.75, c2: 0.4, e2: 0.75)

    // MARK: - 钢铁之路

    /// 钢铁之路：等级 +100，生命 / 护盾 / 护甲 ×2.5。
    /// 来源：<https://wiki.warframe.com/w/The_Steel_Path>
    ///   "All enemies have their level increased by 100, and gain an additional
    ///    +150% (to a total of 250%, or 2.5x) bonus to health and shields."
    /// 注：早期版本护盾被误乘 2.5²，已被修复成 2.5。
    public static let steelPathLevelBonus: Int = 100
    public static let steelPathStatMultiplier: Double = 2.5

    // MARK: - 派系抗性

    /// 派系易伤 / 抗性。Update 36.0 起抗性只按派系判，
    /// 易伤 ×1.5，抗性 ×0.5，其余 ×1.0。
    /// 来源：<https://wiki.warframe.com/w/Damage>（"Simplified Faction Resistances"）
    ///   Grineer: Impact / Corrosive 易伤
    ///   Corpus: Puncture / Magnetic 易伤
    ///   Infested: Slash / Heat 易伤
    ///   Orokin: Puncture / Viral 易伤，Radiation 抗性
    ///   Sentient: Cold / Radiation 易伤，Corrosive 抗性
    ///   Narmer: Slash / Toxin 易伤，Magnetic 抗性
    ///   Zariman: Void 易伤
    ///   Murmur: Electricity / Radiation 易伤，Viral 抗性
    public static let vulnerableMultiplier: Double = 1.5
    public static let resistantMultiplier: Double = 0.5

    // MARK: - 伤害分配

    /// 触发类型按各伤害类型占总伤害的比例抽。
    /// 来源：<https://wiki.warframe.com/w/Status_Effect>（"Damage Distribution"）
    /// 注：Damage 2.0 时代物理类型有 4× 权重，现版本 wiki 已不再这样写；
    /// 这里按**无权重**实现，见 README「待确认项」。
    public static let physicalProcWeight: Double = 1.0
}
