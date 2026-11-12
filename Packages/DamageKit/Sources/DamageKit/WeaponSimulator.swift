import Foundation

/// 单一敌人状态机。
///
/// 每个时间点先结算同一发射事件的全部直伤，再把这次命中的状态写入状态池；
/// 因而同一次开火中的 Viral 不会因为攻击段在数组里的先后位置而抬高同一发的
/// 其它攻击段。随后由同一个状态继续驱动 DOT、护甲变化与下一发伤害。
public struct WeaponSimulator: Sendable {
    public let segments: [ResolvedAttack]
    public let enemy: EnemyProfile
    public let options: Options

    public init(segments: [ResolvedAttack], enemy: EnemyProfile, options: Options) {
        self.segments = segments
        self.enemy = enemy
        self.options = options
    }

    public var faction: FactionProfile { enemy.faction }

    private var resolvedCorrosiveStackCapBonus: Double {
        // Shards are loadout-wide, so every resolved segment normally carries
        // the same value. `max` is defensive for a malformed mixed input and
        // avoids reducing a valid cap merely because another segment has no
        // status generation.
        segments.map(\.corrosiveStackCapBonus).max() ?? 0
    }

    // MARK: - Public surface

    private var runtimes: [SegmentRuntime] {
        segments.map { attack in
            return SegmentRuntime(
                damage: attack.orderedDamage,
                totalDamage: attack.totalDamage,
                critChance: attack.critChance,
                critMultiplier: attack.critMultiplier,
                nonCriticalDamageBonus: attack.nonCriticalDamageBonus,
                nonCriticalDamageChance: attack.nonCriticalDamageChance,
                doubleCritChance: attack.doubleCritChance,
                slashOnCriticalChance: attack.slashOnCriticalChance,
                directDamagePerStatusType: attack.directDamagePerStatusType,
                baseDamageMultiplier: attack.baseDamageMultiplier,
                conditionalDamageIsMultiplicative: attack.conditionalDamageIsMultiplicative,
                headshotMultiplier: attack.headshotMultiplier,
                factionMultiplier: 1 + attack.factionBonus,
                damageVulnerability: attack.damageVulnerabilityMultiplier,
                directDamageMultiplier: attack.directDamageMultiplier,
                weaponVectorDamageMultiplier: attack.weaponVectorDamageMultiplier,
                statusDamageMultiplier: attack.statusDamageMultiplier,
                xataDamageRatio: attack.xataDamageRatio,
                toxicLashDamageRatio: attack.toxicLashDamageRatio,
                toxicLashToxinElementBonus: attack.toxicLashToxinElementBonus,
                toxicLashStatusMultiplier: attack.toxicLashStatusMultiplier,
                stealth: attack.stealth,
                multishot: attack.multishot,
                lastShotMultishot: attack.lastShotMultishot,
                statusChance: attack.statusChance,
                critChancePerCombo: attack.critChancePerCombo,
                statusChancePerCombo: attack.statusChancePerCombo,
                baseCritChanceForCombo: attack.baseCritChanceForCombo,
                baseStatusChanceForCombo: attack.baseStatusChanceForCombo,
                // Damaging statuses seed from Modded Base Damage, not from the
                // final direct-hit vector (which includes elemental/physical mods).
                dotBase: attack.dotBaseDamage,
                dotElementBonuses: attack.dotElementBonuses,
                dotStatusBonuses: attack.dotStatusBonuses,
                statusDamage: (1 + attack.statusDamageBonus)
                    * attack.damageVulnerabilityMultiplier
                    * attack.statusDamageVulnerabilityMultiplier
                    * attack.statusDamageMultiplier,
                statusDuration: attack.statusDuration
            )
        }
    }

    /// 运行一条连续的敌人状态时间线，而非分别把每一层从满值重放一次。
    public func run() -> [AttackResult] {
        let schedules = segments.map { shotSchedule(for: $0) }
        // 防护层/TTK 必须在目标死亡时停止；但 20 秒 DPS、直伤、DOT 与状态次数
        // 是完整射击窗口的输出，不能因为这个特定目标在第 0.5 秒死亡而把剩余
        // 19.5 秒的武器输出清零再除以 20。两条时间线共享同一公式和初始状态。
        let targetOutcome = simulate(schedules: schedules, continuesAfterDeath: false)
        let outputOutcome = simulate(schedules: schedules, continuesAfterDeath: true)

        return segments.indices.map { index in
            var layers: [LayerResult] = []
            for (layerIndex, layer) in Self.damageLayers.enumerated() {
                let maximum = targetOutcome.maxima[layerIndex]
                guard maximum > 0 || targetOutcome.hasTouched(layerIndex: layerIndex, segment: index) else { continue }
                let vector = Self.vector(targetOutcome.byType[layerIndex][index],
                                         touched: targetOutcome.touched[layerIndex][index])
                let damage = vector.totalDamage
                layers.append(LayerResult(layer: layer,
                                          maxHP: maximum,
                                          damage: damage,
                                          dps: damage / max(options.window, 1e-9),
                                          byType: Self.keyed(vector),
                                          // 这是该真实层被打空的时刻。多段攻击共享同一目标时，
                                          // 该值自然是共同的层状态，而不是虚构的分段 TTK。
                                          ttk: targetOutcome.breakTimes[layerIndex]))
            }

            let rawDirect = Self.vector(outputOutcome.rawDirect[index])
            let rawDot = Self.vector(outputOutcome.rawDot[index])
            var rawVector = rawDirect
            for (type, value) in rawDot.ordered { rawVector[type, default: 0] += value }
            let targetDirect = Self.vector(outputOutcome.targetDirect[index])
            let targetDot = Self.vector(outputOutcome.targetDot[index])
            var targetVector = targetDirect
            for (type, value) in targetDot.ordered { targetVector[type, default: 0] += value }

            return AttackResult(
                attack: segments[index].name,
                shots: Double(schedules[index].count),
                dps: (rawDirect.totalDamage + rawDot.totalDamage) / max(options.window, 1e-9),
                directDamage: rawDirect.totalDamage,
                dotDamage: rawDot.totalDamage,
                rawByType: Self.keyed(rawVector),
                targetDps: (targetDirect.totalDamage + targetDot.totalDamage)
                    / max(options.window, 1e-9),
                targetDirectDps: targetDirect.totalDamage / max(options.window, 1e-9),
                targetDirectDamage: targetDirect.totalDamage,
                targetDotDamage: targetDot.totalDamage,
                targetByType: Self.keyed(targetVector),
                layers: layers,
                procs: outputOutcome.procCounts[index],
                notes: segments[index].notes
            )
        }
    }

    /// 定长数组转为稳定排序的伤害向量。
    static func vector(_ row: [Double], touched: [Bool]? = nil) -> [DamageType: Double] {
        var out: [DamageType: Double] = [:]
        for (i, type) in DamageType.allCases.enumerated() where i < row.count {
            if row[i] != 0 {
                out[type] = row[i]
            } else if let touched, i < touched.count, touched[i] {
                out[type] = 0
            }
        }
        return out
    }

    static func keyed(_ vector: [DamageType: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (type, value) in vector.ordered { out[type.rawValue] = value }
        return out
    }

    public struct Shot: Sendable, Equatable {
        public var time: Double
        public var isLastInMagazine: Bool
        /// One button input can contain multiple melee contact events.  This
        /// multiplier belongs to the emitted contact, not to the input view.
        public var damageMultiplier: Double
        /// Stance-specific forced status for this contact.
        public var forcedStatuses: [String]
        /// Current melee combo multiplier for this individual contact.  The
        /// direct hit only consumes it as damage during a heavy attack; combo
        /// action keys also receive it when calculating crit/status chance.
        public var comboMultiplier: Double

        public init(time: Double, isLastInMagazine: Bool,
                    damageMultiplier: Double = 1,
                    forcedStatuses: [String] = [],
                    comboMultiplier: Double = 1) {
            self.time = time
            self.isLastInMagazine = isLastInMagazine
            self.damageMultiplier = damageMultiplier
            self.forcedStatuses = forcedStatuses
            self.comboMultiplier = comboMultiplier
        }
    }

    /// 为 burst 武器逐颗弹丸排程。最后一个 burst 会按弹匣余量截断，绝不凭空
    /// 射出超过弹匣容量的子弹。
    public func shotSchedule(for attack: ResolvedAttack) -> [Shot] {
        if let sequence = attack.meleeSequence {
            return meleeComboSchedule(for: attack, sequence: sequence)
        }
        if attack.chargeTiming == .bow {
            return bowChargeSchedule(for: attack)
        }
        let rate = max(attack.fireRate, 1e-9)
        let shotDelay = 1.0 / rate
        // 对非弓蓄力攻击，完整蓄力与普通 shot delay 都是相邻两发的组成。
        // 第一次命中也必须先等完整蓄力，不能在 t=0 凭空射出满蓄力伤害。
        let interval = shotDelay + (attack.chargeTiming == .standard ? attack.chargeTime : 0)
        let magazine = max(1, Int(ceil(attack.magazine)))
        let reload = max(0, attack.reload)
        let burst = max(1, attack.burstCount)
        let burstDelay = max(0, attack.burstDelay)

        var shots: [Shot] = []
        var t = attack.chargeTiming == .standard ? attack.chargeTime : 0
        var roundsInMagazine = 0
        var guardCount = 0

        while t < options.window - 1e-9 && guardCount < 200_000 {
            let available = max(0, magazine - roundsInMagazine)
            guard available > 0 else { break }
            let count = min(burst, available)
            var lastShotTime = t

            for b in 0..<count {
                let shotTime = t + Double(b) * burstDelay
                lastShotTime = shotTime
                if shotTime < options.window - 1e-9 {
                    let round = roundsInMagazine + b + 1
                    shots.append(Shot(time: shotTime, isLastInMagazine: round == magazine))
                }
            }

            roundsInMagazine += count
            let nominalNextBurst = t + interval * Double(burst)
            if roundsInMagazine >= magazine {
                roundsInMagazine = 0
                // 自动空仓换弹不是在最后一颗弹丸命中时立刻开始：游戏先等待一个
                // `1 / fireRate` 的 reload delay，随后才进入 reload。对单发榴弹
                // 发射器而言，下一发是 `lastShot + 1/fireRate + reload`，不能漏掉
                // 这段射击节奏；对 burst 则仍不能早于正常 burst 周期。
                let reloadReadyAt = lastShotTime + interval + reload
                t = max(nominalNextBurst, reloadReadyAt)
            } else {
                t = nominalNextBurst
            }
            guardCount += 1
        }

        return shots.sorted { $0.time < $1.time }
    }

    /// The website's default melee fallback reports a combo as its individual
    /// contact events.  It derives the number of contacts from combo duration
    /// and spreads those contacts over the selected time window.  Preserve that
    /// contract in the simulator, while retaining per-contact damage/status
    /// data for actual damage resolution.
    private func meleeComboSchedule(for attack: ResolvedAttack,
                                    sequence: MeleeAttackSequence) -> [Shot] {
        let multipliers = sequence.hitMultipliers.filter { $0 > 0 }
        guard !multipliers.isEmpty else { return [] }
        // The source adds heavy wind-up after attack-speed-scaled source-data
        // duration. Normal stance combos have `windUp == 0`.
        let cycle = max(sequence.cycleDuration / max(attack.fireRate, 1e-9)
                        + max(0, sequence.windUp), 1e-9)
        let exactContacts = options.window * Double(multipliers.count) / cycle
        let count = max(0, Int(exactContacts.rounded()))
        guard count > 0 else { return [] }

        let statuses = sequence.normalizedStatuses
        let comboMultipliers = meleeComboMultipliers(for: attack, contactCount: count,
                                                     heavyHitCount: multipliers.count)
        return (0..<count).map { index in
            let position = index % multipliers.count
            let status = position < statuses.count ? statuses[position] : ""
            let comboMultiplier = comboMultipliers[index]
            return Shot(time: options.window * Double(index) / Double(count),
                        isLastInMagazine: false,
                        damageMultiplier: multipliers[position]
                            * (attack.isHeavyMeleeAttack ? comboMultiplier : 1),
                        forcedStatuses: status.isEmpty ? [] : [status],
                        comboMultiplier: comboMultiplier)
        }
    }

    /// Recreates the website's repeated-heavy contact timeline in pure Swift.
    /// Combo is stored in points (20 points = one x-combo step); every group
    /// of `floor(0.8 * contacts/seconds) + heavyHitCount` contacts consumes it
    /// and Heavy Attack Efficiency retains its declared fraction.  A normal
    /// melee sequence receives the user-selected multiplier only for combo
    /// dependent Mod actions, never as an unconditional damage multiplier.
    private func meleeComboMultipliers(for attack: ResolvedAttack, contactCount: Int,
                                       heavyHitCount: Int) -> [Double] {
        guard attack.isHeavyMeleeAttack else {
            return Array(repeating: max(1, attack.meleeComboMultiplier), count: contactCount)
        }

        let startMultiplier = min(max(attack.heavyStartingComboMultiplier, 1), 13)
        let startPoints = 20 * (startMultiplier - 1)
        let cappedInitialPoints = min(max(attack.initialComboPoints, 0), 20 * startMultiplier)
        var points = max(startPoints, cappedInitialPoints)
        let contactsBeforeConsume = max(1,
            Int((0.8 * Double(contactCount) / max(options.window, 1e-9)).rounded(.towardZero))
                + max(1, heavyHitCount))
        var remaining = contactsBeforeConsume
        var result: [Double] = []
        result.reserveCapacity(contactCount)

        for _ in 0..<contactCount {
            if remaining == 0 {
                remaining = contactsBeforeConsume
                points = max(points * attack.heavyComboEfficiency, cappedInitialPoints)
                if points < 20 { points = 0 }
            }
            result.append(max(1, Double(Int(1 + points / 20))))
            remaining -= 1
        }
        return result
    }

    /// Bow 的满蓄力每一发均消耗一支箭并立即进入 reload；社区公式的有效射速为
    /// `1 / (modded charge time + modded reload time)`。它没有普通武器空仓时
    /// 那段额外的 `1 / fireRate` reload delay，因此不能复用上面的通用弹匣循环。
    private func bowChargeSchedule(for attack: ResolvedAttack) -> [Shot] {
        let charge = max(0, attack.chargeTime)
        let cycle = max(charge + max(0, attack.reload), 1e-9)
        var shots: [Shot] = []
        var t = charge
        var guardCount = 0
        while t < options.window - 1e-9 && guardCount < 200_000 {
            shots.append(Shot(time: t, isLastInMagazine: true))
            t += cycle
            guardCount += 1
        }
        return shots
    }

    // MARK: - State

    /// Armor 不是可扣减的生命层；真实可被伤害路由消耗的只有这三层。
    private static let damageLayers: [Layer] = [.overguard, .shield, .health]

    private struct StackEntry {
        var expiry: Double
        var weight: Double
    }

    /// A status stack's expected count is enough for armor, Viral, Cold, etc.,
    /// but Galvanized Shot asks a different question: whether a *type* exists
    /// at all. Keep the independent event probabilities so the expectation of
    /// the number of unique active types remains exact.
    private struct PresenceEntry {
        var expiry: Double
        var probability: Double
    }

    /// Heat's armor strip is a single target state, not one independent strip
    /// per Heat DOT.  Re-proccing refreshes its lifetime but never accelerates
    /// the 15/30/40/50% ramp.
    private struct HeatArmorState {
        var startedAt: Double
        var activeUntil: Double
        var rampStep: Double
    }

    private struct HeatContribution {
        var normalizedSeed: Double
        var weight: Double
        var segment: Int
        var startedAt: Double
    }

    /// Heat 的所有活跃层在游戏中合成同一跳；重复施加会刷新整组持续时间。
    /// Individual contributions are retained so an enemy-specific finite proc
    /// cap can replace the oldest Heat stack rather than silently discard it.
    private struct HeatDotState {
        var contributions: [HeatContribution]
        var firstSegment: Int
        var firstElementBonus: Double
        var firstFactionMultiplier: Double
        var firstStatusMultiplier: Double
        var nextTick: Double
        var activeUntil: Double
    }

    /// Electricity shares Heat's one-accumulator rule only inside an individual
    /// pulse.  Unlike Heat, it does not refresh into one target-wide timer:
    /// every proc contribution keeps its own expiry while contributions born on
    /// the same pulse are displayed and resolved as one damage event.
    private struct TeslaContribution {
        /// The ordinary weapon-DoT seed.  It participates in the group's one
        /// `+1` accumulator.  Magnetic shield-break damage is already a
        /// documented total, so it enters through `fixedPerTick` instead.
        var normalizedSeed: Double
        var fixedPerTick: Double
        var usesAccumulator: Bool
        var weight: Double
        var segment: Int
        var startedAt: Double
        var activeUntil: Double
    }

    private struct TeslaDotState {
        var contributions: [TeslaContribution]
        var firstSegment: Int
        var firstElementBonus: Double
        var firstFactionMultiplier: Double
        var firstStatusMultiplier: Double
        var nextTick: Double
    }

    /// Gas stacks have independent timers, but all contributions due on the
    /// same pulse are one Gas tick group.  This is intentionally not Heat's
    /// refreshable target-wide timer and not Slash/Toxin's independent ticks.
    private struct GasContribution {
        var normalizedSeed: Double
        var weight: Double
        var segment: Int
        var startedAt: Double
        var activeUntil: Double
    }

    private struct GasDotState {
        var contributions: [GasContribution]
        var firstSegment: Int
        var firstElementBonus: Double
        var firstFactionMultiplier: Double
        var firstStatusMultiplier: Double
        var nextTick: Double
    }

    /// Magnetic's shield/Overguard-break Electricity belongs to the weapon
    /// that applied Magnetic, not necessarily to the hit that drained the
    /// layer.  Keep that source on each stack so mixed sources remain
    /// attributable instead of borrowing the breaker’s mods.
    private struct MagneticSource {
        var segment: Int
        var electricityElementBonus: Double
        var electricityStatusMultiplier: Double
        var factionMultiplier: Double
        var statusDuration: Double
    }

    private struct MagneticStackEntry {
        var expiry: Double
        var weight: Double
        var startedAt: Double
        var source: MagneticSource
    }

    private struct DotInstance {
        var kind: ProcKind
        /// Routing can differ from the damage type that supplies resistance /
        /// faction modifiers: Slash status routes as Cinematic damage.
        var type: DamageType
        var modifierType: DamageType
        /// Per one status stack.  `weight` is fractional only in the analytic
        /// expected-value mode; a concrete proc is weight 1.
        var perTick: Double
        var weight: Double
        var start: Double
        var nextTick: Double
        var ticksLeft: Int
        var segment: Int
        /// Toxic Lash's site rule first derives a layer-adjusted weapon hit,
        /// then creates its own Toxin damage.  Its tick must therefore bypass
        /// the ordinary Toxin element/armor pass while retaining Toxin's shield
        /// bypass and target-layer routing.
        var preMitigatedToxin: Bool
    }

    private struct SegmentRuntime {
        let damage: [DamageEntry]
        let totalDamage: Double
        let critChance: Double
        let critMultiplier: Double
        let nonCriticalDamageBonus: Double
        let nonCriticalDamageChance: Double
        let doubleCritChance: Double
        let slashOnCriticalChance: Double
        let directDamagePerStatusType: Double
        let baseDamageMultiplier: Double
        let conditionalDamageIsMultiplicative: Bool
        let headshotMultiplier: Double
        let factionMultiplier: Double
        let damageVulnerability: Double
        let directDamageMultiplier: Double
        let weaponVectorDamageMultiplier: Double
        let statusDamageMultiplier: Double
        let xataDamageRatio: Double
        let toxicLashDamageRatio: Double
        let toxicLashToxinElementBonus: Double
        let toxicLashStatusMultiplier: Double
        let stealth: Bool
        let multishot: Double
        let lastShotMultishot: Double
        let statusChance: Double
        let critChancePerCombo: Double
        let statusChancePerCombo: Double
        let baseCritChanceForCombo: Double
        let baseStatusChanceForCombo: Double
        let dotBase: Double
        let dotElementBonuses: [DamageType: Double]
        let dotStatusBonuses: [DamageType: Double]
        let statusDamage: Double
        let statusDuration: Double

        func multishot(lastInMagazine: Bool) -> Double {
            lastInMagazine ? multishot + lastShotMultishot : multishot
        }

        func critValues(coldStacks: Double, punctureStacks: Double,
                        comboMultiplier: Double = 1) -> (chance: Double, multiplier: Double) {
            // `crit_chance_per_combo` is a relative base-critical term.  Its
            // input is the actual contact's x-combo minus one, not a value the
            // UI has turned into direct damage.
            let comboSteps = max(0, comboMultiplier - 1)
            let comboBonus = baseCritChanceForCombo * critChancePerCombo * comboSteps
            let cc = critChance + comboBonus + 0.05 * min(max(punctureStacks, 0), 5)
            let cdm = critMultiplier + WeaponSimulator.coldCriticalDamageBonus(stacks: coldStacks)
            return (max(0, cc), max(1, cdm))
        }

        func hitMultiplier(coldStacks: Double, punctureStacks: Double,
                           comboMultiplier: Double = 1) -> Double {
            let crit = critValues(coldStacks: coldStacks, punctureStacks: punctureStacks,
                                  comboMultiplier: comboMultiplier)
            let cc = crit.chance
            let cdm = crit.multiplier
            // 非暴击概率在 CC 达到 100% 后为 0；不能用 `1 - cc`，否则橙暴/红暴会
            // 把这个只作用于非暴击的灵化效果错误地变成负数。
            let nonCriticalProbability = max(0, 1 - min(max(cc, 0), 1))
            let attrition = nonCriticalProbability * nonCriticalDamageChance * nonCriticalDamageBonus
            // Vigilante 的升阶只会发生在已经暴击的弹丸上。每升一档都额外增加
            // `CDM - 1`；无论基础是黄暴、橙暴还是红暴，这个增量相同。
            let vigilante = min(max(doubleCritChance, 0), 1) * min(cc, 1)
            let ordinary: Double
            if headshotMultiplier > 1 {
                ordinary = Rules.expectedCriticalHeadshotMultiplier(critChance: cc,
                                                                     critDamage: cdm,
                                                                     headshotMultiplier: headshotMultiplier)
                    + headshotMultiplier * vigilante * (2 * cdm - 1)
                    + headshotMultiplier * attrition
            } else {
                ordinary = Rules.expectedCritMultiplier(critChance: cc, critDamage: cdm)
                    + vigilante * (cdm - 1) + attrition
            }

            // warframe-damage applies `getStealthDmgBonus` to the actual
            // critical result after Cold/Puncture adjustments.  For an
            // ordinary body hit it maps a non-crit 1× to 7× and every crit
            // result r to r+7.  Thus its expectation is ordinary + 7 - P0,
            // where P0 is the chance to stay at the non-crit tier.  Critical
            // headshots already contain their head multiplier, while an
            // ordinary headshot is still multiplied outside that critical
            // result; the website consequently contributes 6H for a non-crit
            // and +7 for a crit.  Keeping this in the simulator (rather than
            // BuildResolver) preserves dynamic Cold/Puncture stack behavior.
            guard stealth else { return ordinary }
            let nonCritical = nonCriticalProbability
            if headshotMultiplier > 1 {
                return ordinary + 6 * headshotMultiplier * nonCritical + 7 * (1 - nonCritical)
            }
            return ordinary + 7 - nonCritical
        }

        /// Hunter Munitions 的 Slash 只在暴击命中上生成，因此不能把无条件的
        /// 期望伤害倍率拿来当 DOT seed。这里返回“已知这次命中为暴击”时的
        /// 平均倍率，并包含 Vigilante 可能再升一档的期望。
        func criticalProcSeedMultiplier(coldStacks: Double, punctureStacks: Double,
                                        comboMultiplier: Double = 1) -> Double {
            let crit = critValues(coldStacks: coldStacks, punctureStacks: punctureStacks,
                                  comboMultiplier: comboMultiplier)
            let base = Rules.expectedCritMultiplier(critChance: max(1, crit.chance),
                                                    critDamage: crit.multiplier)
            let vigilante = min(max(doubleCritChance, 0), 1) * (crit.multiplier - 1)
            // This path is conditioned on a critical hit, so it always uses
            // the website's r -> r+7 branch (never the non-critical 1 -> 7
            // branch).  A critical headshot already contains its headshot
            // multiplier before the +7 is applied.
            return headshotMultiplier * (base + vigilante) + (stealth ? 7 : 0)
        }

        func statusChanceFor(comboMultiplier: Double) -> Double {
            let comboSteps = max(0, comboMultiplier - 1)
            // `status_chance_by_combo` is likewise relative to the unmodified
            // attack chance.  The static action modifiers are already in
            // `statusChance`; this is the per-contact delta.
            return max(0, statusChance
                + baseStatusChanceForCombo * statusChancePerCombo * comboSteps)
        }
    }

    private struct State {
        /// [overguard, shield, health]
        var pools: [Double]
        let maxima: [Double]
        var breakTimes: [Double?]
        var shieldGateUntil: Double = -.infinity

        /// [layer][segment][damage type]
        var byType: [[[Double]]]
        var touched: [[[Bool]]]
        var rawDirect: [[Double]]
        var rawDot: [[Double]]
        /// 相同射击窗口中、通过目标生命层倍率之后的未截断承伤。这个账本
        /// 仅用于持续有效 DPS；`byType` 仍是实际有限血量目标所承受的伤害。
        var targetDirect: [[Double]]
        var targetDot: [[Double]]
        var procCounts: [[String: Double]]
        var dots: [DotInstance] = []
        var stacks: [ProcKind: [StackEntry]] = [:]
        /// Probability-bearing status events, used only for unique-status
        /// checks. Counts above remain the expected stack counts used by the
        /// normal status formulae.
        var statusPresence: [ProcKind: [PresenceEntry]] = [:]
        var heatArmor: HeatArmorState?
        var heatDot: HeatDotState?
        var teslaDots: [TeslaDotState] = []
        var gasDots: [GasDotState] = []
        var magneticStacks: [MagneticStackEntry] = []
        /// 输出时间线在目标已死后仍继续生成武器输出；防护层统计使用另一条
        /// `continuesAfterDeath == false` 的时间线，不会受此影响。
        let continuesAfterDeath: Bool

        init(enemy: EnemyProfile, segmentCount: Int, continuesAfterDeath: Bool = false) {
            let pools = [enemy.overguard, enemy.shield, enemy.health].map { max(0, $0) }
            let typeCount = DamageType.count
            self.pools = pools
            maxima = pools
            breakTimes = Array<Double?>(repeating: nil, count: pools.count)
            byType = Array(repeating: Array(repeating: Array(repeating: 0, count: typeCount), count: segmentCount),
                           count: pools.count)
            touched = Array(repeating: Array(repeating: Array(repeating: false, count: typeCount), count: segmentCount),
                            count: pools.count)
            rawDirect = Array(repeating: Array(repeating: 0, count: typeCount), count: segmentCount)
            rawDot = Array(repeating: Array(repeating: 0, count: typeCount), count: segmentCount)
            targetDirect = Array(repeating: Array(repeating: 0, count: typeCount), count: segmentCount)
            targetDot = Array(repeating: Array(repeating: 0, count: typeCount), count: segmentCount)
            procCounts = Array(repeating: [:], count: segmentCount)
            self.continuesAfterDeath = continuesAfterDeath
        }

        var isAlive: Bool { continuesAfterDeath || pools[Self.healthIndex] > 1e-9 }
        static let overguardIndex = 0
        static let shieldIndex = 1
        static let healthIndex = 2
    }

    private struct Outcome {
        var maxima: [Double]
        var breakTimes: [Double?]
        var byType: [[[Double]]]
        var touched: [[[Bool]]]
        var rawDirect: [[Double]]
        var rawDot: [[Double]]
        var targetDirect: [[Double]]
        var targetDot: [[Double]]
        var procCounts: [[String: Double]]

        func hasTouched(layerIndex: Int, segment: Int) -> Bool {
            byType[layerIndex][segment].contains { $0 != 0 }
                || touched[layerIndex][segment].contains(true)
        }
    }

    private struct PendingProc {
        let segment: Int
        let kind: ProcKind
        let type: DamageType
        /// Expected count carried into the existing analytic status model.
        let count: Double
        /// Probability that this projectile contributes at least one instance
        /// of the type. It deliberately differs from `count` above one
        /// guaranteed status roll.
        let presenceProbability: Double
        let seed: Double
    }

    /// Enemy shield gating only attenuates a normal direct damage instance.
    /// Damage instances created by that hit (for example status ticks) remain
    /// independently routable through the target state.
    private enum DamageEventKind {
        case direct
        case status
    }

    // MARK: - Timeline

    private func simulate(schedules: [[Shot]], continuesAfterDeath: Bool) -> Outcome {
        let runtimes = self.runtimes
        var state = State(enemy: enemy, segmentCount: segments.count,
                          continuesAfterDeath: continuesAfterDeath)
        var pointers = Array(repeating: 0, count: schedules.count)
        seedInitialStatusStacks(&state)

        while state.isAlive {
            var nextShot = Double.infinity
            for i in schedules.indices where pointers[i] < schedules[i].count {
                nextShot = min(nextShot, schedules[i][pointers[i]].time)
            }
            var nextDot = Double.infinity
            for dot in state.dots { nextDot = min(nextDot, dot.nextTick) }
            if let heat = state.heatDot, heat.nextTick <= heat.activeUntil + 1e-9 {
                nextDot = min(nextDot, heat.nextTick)
            }
            for tesla in state.teslaDots {
                nextDot = min(nextDot, tesla.nextTick)
            }
            for gas in state.gasDots {
                nextDot = min(nextDot, gas.nextTick)
            }
            let t = min(nextShot, nextDot)
            guard t < options.window - 1e-9 else { break }

            // Existing DoT ticks at this timestamp land before the new hit.  A
            // newly created Electricity/Gas proc at t will then be processed on
            // the next queue pass at that same t.
            if nextDot <= nextShot + 1e-9 {
                tickDots(&state, at: t)
            } else {
                var pending: [PendingProc] = []
                // Components emitted by one trigger may share a status pool for
                // later shots, but a proc created by component A cannot amplify
                // component B at the same timestamp. Each component therefore
                // starts from this snapshot; projectiles *inside* that component
                // are still resolved in their documented order below.
                let stateAtTimestamp = state

                for segment in schedules.indices where pointers[segment] < schedules[segment].count {
                    let shot = schedules[segment][pointers[segment]]
                    guard abs(shot.time - t) <= 1e-9 else { continue }
                    var conditionState = stateAtTimestamp
                    pending += fireDirect(&state, conditionState: &conditionState,
                                          segment: segment, at: t, shot: shot,
                                          runtimes: runtimes)
                    pointers[segment] += 1
                }

                // Commit all status events after every direct component in this
                // firing event. `fireDirect` already used an isolated shadow
                // state to let projectile n affect projectile n+1 only.
                for item in pending where state.isAlive {
                    spawn(kind: item.kind, type: item.type, count: item.count,
                          presenceProbability: item.presenceProbability, seed: item.seed,
                          at: t, segment: item.segment, state: &state, runtimes: runtimes)
                }
            }
        }

        return Outcome(maxima: state.maxima,
                       breakTimes: state.breakTimes,
                       byType: state.byType,
                       touched: state.touched,
                       rawDirect: state.rawDirect,
                       rawDot: state.rawDot,
                       targetDirect: state.targetDirect,
                       targetDot: state.targetDot,
                       procCounts: state.procCounts)
    }

    /// Resolve one trigger as ordered projectiles.  `state` receives the direct
    /// damage; `conditionState` is a local status timeline so an earlier pellet
    /// can feed Galvanized Shot, Viral, Corrosive, Cold and Puncture into the
    /// next pellet without leaking those newly-created statuses to a separate
    /// simultaneous attack segment.
    private func fireDirect(_ state: inout State, conditionState: inout State,
                            segment: Int, at t: Double, shot: Shot,
                            runtimes: [SegmentRuntime]) -> [PendingProc] {
        guard state.isAlive else { return [] }
        let attack = runtimes[segment]
        let multishot = attack.multishot(lastInMagazine: shot.isLastInMagazine)
        var pending: [PendingProc] = []

        for projectileWeight in projectileWeights(multishot) where state.isAlive {
            let normalTargetDirectBefore = state.targetDirect[segment].reduce(0, +)
            let hitMultiplier = attack.hitMultiplier(
                coldStacks: stackCount(.freeze, at: t, state: conditionState),
                punctureStacks: stackCount(.weakened, at: t, state: conditionState),
                comboMultiplier: shot.comboMultiplier
            )
            let conditionalBonus = attack.directDamagePerStatusType
                * activeStatusTypeCount(at: t, state: conditionState)
            // Galvanized Shot / Gun CO is normally additive with base-damage
            // mods. `attack.damage` already contains `baseDamageMultiplier`,
            // so normalize the augmented additive pool instead of multiplying
            // that entire pool a second time.  The data's `isCoMult` flag is
            // the documented exception that uses an independent multiplier.
            let conditionMultiplier: Double
            if attack.conditionalDamageIsMultiplicative {
                conditionMultiplier = 1 + conditionalBonus
            } else {
                conditionMultiplier = (attack.baseDamageMultiplier + conditionalBonus)
                    / max(attack.baseDamageMultiplier, 1e-12)
            }
            let scale = hitMultiplier * attack.factionMultiplier * attack.damageVulnerability
                * attack.directDamageMultiplier
                * attack.weaponVectorDamageMultiplier
                * projectileWeight * conditionMultiplier * shot.damageMultiplier

            for entry in attack.damage {
                let weaponSide = entry.value * scale
                state.rawDirect[segment][entry.type.index] += weaponSide
                let incoming = weaponSide
                    * faction.multiplier(for: entry.type)
                    * enemy.elementalResistance(entry.type)
                route(&state, segment: segment, type: entry.type, incoming: incoming,
                      at: t, event: .direct)
                if !state.isAlive { break }
            }
            guard state.isAlive else { break }
            let normalTargetDirect = max(0, state.targetDirect[segment].reduce(0, +)
                - normalTargetDirectBefore)

            // Xata's Whisper is its own Void hit rather than an extra weapon
            // elemental component.  The website derives it from the modded
            // weapon-vector total before Gun CO, uses the hit's crit/shot
            // factors, and applies the generic faction multiplier a second
            // time.  It deliberately does not receive the faction profile's
            // per-element weakness table: source `getXataDmg` only routes the
            // Void hit through the selected defense layer and innate DR.
            if attack.xataDamageRatio > 0 {
                let xataScale = hitMultiplier
                    * attack.factionMultiplier * attack.factionMultiplier
                    * attack.damageVulnerability
                    * attack.directDamageMultiplier
                    * projectileWeight * shot.damageMultiplier
                let xataRaw = attack.totalDamage * attack.xataDamageRatio * xataScale
                if xataRaw > 0 {
                    state.rawDirect[segment][DamageType.void.index] += xataRaw
                    route(&state, segment: segment, type: .void, incoming: xataRaw,
                          at: t, event: .direct)
                }
            }

            // Toxic Lash is not an ordinary chance-based weapon Toxin proc.
            // Every projectile creates a separately rounded Toxin hit and a
            // seven-tick instance.  The website derives the effect from the
            // modded weapon-vector total before Gun CO, gives a melee weapon a
            // 2x resolved ratio, and applies the generic faction multiplier
            // once more to the direct hit and once again to its tick.
            if attack.toxicLashDamageRatio > 0 {
                // Source `toxicLashDmg` receives the same layer-adjusted
                // weapon-hit total used for that website defense queue, not a
                // fresh standalone Toxin elemental vector.  Reusing the
                // resolved normal hit keeps physical/type bonuses and armor in
                // the same position, then applies Toxic Lash's extra faction
                // stage and per-projectile rounding.
                let toxicLashBase = normalTargetDirect
                    * attack.factionMultiplier * attack.toxicLashDamageRatio
                let toxicLashDirect = ceil(toxicLashBase)
                if toxicLashDirect > 0 {
                    state.rawDirect[segment][DamageType.toxin.index] += toxicLashDirect
                    routePreMitigatedToxin(&state, segment: segment, incoming: toxicLashDirect,
                                            at: t, event: .direct)
                }

                let toxicLashTick = ceil(toxicLashBase
                    * attack.factionMultiplier
                    * 0.5 * (1 + attack.toxicLashToxinElementBonus)
                    * attack.toxicLashStatusMultiplier)
                if toxicLashTick > 0 {
                    // A Toxic Lash tick has already consumed its special source
                    // factors.  It still routes as Toxin (including shield
                    // bypass), but must not receive a second ordinary Toxin
                    // faction/element/armor modifier from `tickDots`.
                    appendDots(&state, kind: .poison, type: .toxin, modifierType: .true,
                               count: projectileWeight, perTick: toxicLashTick, at: t,
                               ticks: 7, segment: segment, firstTickDelay: 1,
                               preMitigatedToxin: true)
                }
            }

            let pelletEvents = projectileProcEvents(segment: segment, attack: attack,
                                                     projectileWeight: projectileWeight,
                                                     hitMultiplier: hitMultiplier * shot.damageMultiplier,
                                                     extraForceProcs: shot.forcedStatuses,
                                                     comboMultiplier: shot.comboMultiplier,
                                                     at: t, state: conditionState)
            // Feed this pellet's statuses into the shadow state before the next
            // projectile. The same events are replayed on the real state only
            // after all simultaneous attack segments have dealt direct damage.
            for event in pelletEvents {
                spawn(kind: event.kind, type: event.type, count: event.count,
                      presenceProbability: event.presenceProbability, seed: event.seed,
                      at: t, segment: event.segment, state: &conditionState, runtimes: runtimes)
            }
            pending += pelletEvents
        }
        return pending
    }

    private func projectileWeights(_ multishot: Double) -> [Double] {
        let value = max(0, multishot)
        let guaranteed = Int(floor(value))
        var weights = Array(repeating: 1.0, count: guaranteed)
        let fractional = value - Double(guaranteed)
        if fractional > 1e-12 { weights.append(fractional) }
        return weights
    }

    /// Expected status events created by one projectile.  The expected stack
    /// count and the chance a type exists are not interchangeable when status
    /// chance exceeds 100%, hence both are carried in PendingProc.
    private func projectileProcEvents(segment: Int, attack: SegmentRuntime,
                                      projectileWeight: Double, hitMultiplier: Double,
                                      extraForceProcs: [String] = [],
                                      comboMultiplier: Double = 1,
                                      at t: Double, state: State) -> [PendingProc] {
        guard projectileWeight > 1e-12 else { return [] }
        var forcedTypes: [DamageType] = []
        for raw in segments[segment].forceProcs {
            guard let type = DamageType(dataKey: raw), !forcedTypes.contains(type) else { continue }
            forcedTypes.append(type)
        }
        for raw in extraForceProcs {
            guard let type = DamageType(dataKey: raw), !forcedTypes.contains(type) else { continue }
            forcedTypes.append(type)
        }
        var events: [PendingProc] = []
        let chance = attack.statusChanceFor(comboMultiplier: comboMultiplier)

        if chance > 0 {
            var weights: [(DamageType, ProcKind, Double)] = []
            var total = 0.0
            for entry in attack.damage {
                guard let kind = ProcKind(damageType: entry.type),
                      !isImmune(entry.type, state: state), entry.value > 0 else {
                    continue
                }
                weights.append((entry.type, kind, entry.value))
                total += entry.value
            }
            if total > 0 {
                let guaranteedRolls = floor(chance)
                let fractionalRoll = chance - guaranteedRolls
                for (type, kind, value) in weights {
                    let typeChance = value / total
                    let noType = pow(max(0, 1 - typeChance), guaranteedRolls)
                        * max(0, 1 - typeChance * fractionalRoll)
                    // A forced proc of the same type is enough to establish its
                    // presence, so do not combine two correlated probabilities
                    // from this one possibly-fractional projectile.
                    let presence = forcedTypes.contains(type)
                        ? 0
                        : projectileWeight * (1 - noType)
                    events.append(PendingProc(segment: segment, kind: kind, type: type,
                                               count: projectileWeight * chance * typeChance,
                                               presenceProbability: presence,
                                               seed: attack.dotBase * hitMultiplier))
                }
            }
        }

        // Forced procs are additional guaranteed events per projectile; they
        // do not replace ordinary status rolls.
        for type in forcedTypes {
            guard let kind = ProcKind(damageType: type), !isImmune(type, state: state) else { continue }
            events.append(PendingProc(segment: segment, kind: kind, type: type,
                                       count: projectileWeight,
                                       presenceProbability: projectileWeight,
                                       seed: attack.dotBase * hitMultiplier))
        }

        // Hunter Munitions is not part of the weapon's ordinary status table:
        // every critical projectile independently has its listed chance to add
        // a Slash status.  Its DOT seed is conditioned on that critical hit,
        // rather than the unconditional direct-hit expectation above.
        if attack.slashOnCriticalChance > 0, !isImmune(.slash, state: state) {
            let cold = stackCount(.freeze, at: t, state: state)
            let puncture = stackCount(.weakened, at: t, state: state)
            let crit = attack.critValues(coldStacks: cold, punctureStacks: puncture,
                                         comboMultiplier: comboMultiplier)
            let criticalProbability = min(max(crit.chance, 0), 1)
            let procProbability = projectileWeight * criticalProbability
                * min(max(attack.slashOnCriticalChance, 0), 1)
            if procProbability > 1e-12 {
                events.append(PendingProc(segment: segment, kind: .bleed, type: .slash,
                                           count: procProbability,
                                           presenceProbability: procProbability,
                                           seed: attack.dotBase * attack.criticalProcSeedMultiplier(
                                               coldStacks: cold, punctureStacks: puncture,
                                               comboMultiplier: comboMultiplier)))
            }
        }
        return events
    }

    /// Galvanized Shot counts distinct active status types, not their layer count.
    /// Each type contributes its probability of existing, not its expected stack
    /// count. This is read before the current projectile's procs are inserted,
    /// matching the rule that a new proc does not amplify the hit that created it.
    private func activeStatusTypeCount(at t: Double, state: State) -> Double {
        // warframe-damage's manual status-count switch is an override, not an
        // additional hidden proc list.  It intentionally changes only the
        // CO/Gun-CO query and leaves Viral, Corrosive, Heat, etc. to the actual
        // target-state timeline supplied by the caller.
        if let manual = options.manualStatusTypeCount {
            return max(0, manual)
        }
        var total = 0.0
        var represented = Set<ProcKind>()
        for (kind, entries) in state.statusPresence {
            represented.insert(kind)
            var absent = 1.0
            for entry in entries where entry.expiry > t + 1e-9 {
                absent *= 1 - min(max(entry.probability, 0), 1)
            }
            total += 1 - absent
        }

        // Backward-compatible fallback for status state that originated before
        // the presence ledger. Normal simulator paths populate both forms.
        var kinds = Set<ProcKind>()
        for (kind, entries) in state.stacks {
            if !represented.contains(kind),
               entries.contains(where: { $0.weight > 1e-12 && $0.expiry > t + 1e-9 }) {
                kinds.insert(kind)
            }
        }
        if !represented.contains(.ignite),
           (state.heatArmor?.activeUntil ?? -.infinity) > t + 1e-9 { kinds.insert(.ignite) }
        if !represented.contains(.ignite),
           (state.heatDot?.activeUntil ?? -.infinity) > t + 1e-9 { kinds.insert(.ignite) }
        if state.dots.contains(where: { $0.ticksLeft > 0 }) {
            for dot in state.dots where dot.ticksLeft > 0 && !represented.contains(dot.kind) {
                kinds.insert(dot.kind)
            }
        }
        if !represented.contains(.tesla),
           state.teslaDots.contains(where: { $0.contributions.contains(where: { $0.activeUntil > t + 1e-9 }) }) {
            kinds.insert(.tesla)
        }
        if !represented.contains(.gasCloud),
           state.gasDots.contains(where: { $0.contributions.contains(where: { $0.activeUntil > t + 1e-9 }) }) {
            kinds.insert(.gasCloud)
        }
        if !represented.contains(.disrupt),
           state.magneticStacks.contains(where: { $0.weight > 1e-12 && $0.expiry > t + 1e-9 }) {
            kinds.insert(.disrupt)
        }
        return total + Double(kinds.count)
    }

    // MARK: - Damage routing

    /// Routes a single damage component through the actual protection order:
    /// Overguard -> Shield -> Health, with Toxin/True bypassing only Shield.
    private func route(_ state: inout State, segment: Int, type: DamageType,
                       incoming: Double, at t: Double, event: DamageEventKind) {
        guard state.isAlive else { return }
        guard incoming > 0 else {
            // Keep a zero in the result vector for a type that was present but
            // fully negated by resistance, rather than making it look absent.
            markFirstRoutedLayer(&state, segment: segment, type: type)
            return
        }
        var remaining = incoming

        if state.pools[State.overguardIndex] > 1e-9 {
            remaining = applyToLayer(&state, layerIndex: State.overguardIndex, segment: segment,
                                     type: type, incoming: remaining, at: t, extraMultiplier: 1,
                                     event: event)
            guard remaining > 1e-12 else { return }
        }

        if !Rules.bypassesShield(type), state.pools[State.shieldIndex] > 1e-9 {
            remaining = applyToLayer(&state, layerIndex: State.shieldIndex, segment: segment,
                                     type: type, incoming: remaining, at: t, extraMultiplier: 1,
                                     event: event)
            guard remaining > 1e-12 else { return }
        }

        // Toxin/True bypass the shield and do not get shield-gate attenuation. A
        // normal direct body hit that reaches health during the enemy's gate is
        // limited to 5%; status damage is a separate instance and is not gated.
        let bypassesGate = Rules.bypassesShield(type)
        let gateActive = t < state.shieldGateUntil - 1e-9
        let isDirect: Bool
        if case .direct = event { isDirect = true } else { isDirect = false }
        let gateMultiplier = (isDirect && !bypassesGate && gateActive
                              && !(options.headshot || options.weakPoint))
            ? Rules.enemyShieldGateHealthFraction : 1
        _ = applyToLayer(&state, layerIndex: State.healthIndex, segment: segment,
                         type: type, incoming: remaining, at: t, extraMultiplier: gateMultiplier,
                         event: event)
    }

    /// Route a Toxic Lash amount that was already calculated against the
    /// current website defense queue.  It preserves the real target order and
    /// Toxin's shield bypass, but intentionally skips ordinary per-element,
    /// innate-DR and armor multiplication; applying those a second time is the
    /// source of the historical armor mismatch for this effect.
    private func routePreMitigatedToxin(_ state: inout State, segment: Int, incoming: Double,
                                        at t: Double, event: DamageEventKind) {
        guard state.isAlive, incoming > 0 else { return }
        var remaining = incoming
        if state.pools[State.overguardIndex] > 1e-9 {
            remaining = applyPreMitigatedToxinToLayer(&state, layerIndex: State.overguardIndex,
                                                       segment: segment, incoming: remaining,
                                                       at: t, event: event)
            guard remaining > 1e-12 else { return }
        }
        _ = applyPreMitigatedToxinToLayer(&state, layerIndex: State.healthIndex,
                                          segment: segment, incoming: remaining, at: t, event: event)
    }

    private func applyPreMitigatedToxinToLayer(_ state: inout State, layerIndex: Int,
                                                segment: Int, incoming: Double, at t: Double,
                                                event: DamageEventKind) -> Double {
        guard incoming > 0 else { return 0 }
        let type = DamageType.toxin
        let slot = type.index
        state.touched[layerIndex][segment][slot] = true
        let potential = incoming
        if layerIndex == State.healthIndex {
            switch event {
            case .direct:
                state.targetDirect[segment][slot] += potential
            case .status:
                state.targetDot[segment][slot] += potential
            }
        }
        let pool = max(0, state.pools[layerIndex])
        let dealt = min(potential, pool)
        state.byType[layerIndex][segment][slot] += dealt
        state.pools[layerIndex] = max(0, pool - dealt)
        if state.pools[layerIndex] <= 1e-9, pool > 1e-9 {
            if state.breakTimes[layerIndex] == nil { state.breakTimes[layerIndex] = t }
            if layerIndex == State.overguardIndex {
                triggerMagneticBreak(&state, maximumLayer: state.maxima[layerIndex], at: t)
            }
        }
        return max(0, potential - dealt)
    }

    private func markFirstRoutedLayer(_ state: inout State, segment: Int, type: DamageType) {
        let layerIndex: Int
        if state.pools[State.overguardIndex] > 1e-9 {
            layerIndex = State.overguardIndex
        } else if !Rules.bypassesShield(type), state.pools[State.shieldIndex] > 1e-9 {
            layerIndex = State.shieldIndex
        } else {
            layerIndex = State.healthIndex
        }
        state.touched[layerIndex][segment][type.index] = true
    }

    /// Applies incoming pre-layer damage to one pool and returns the pre-layer remainder.
    private func applyToLayer(_ state: inout State, layerIndex: Int, segment: Int,
                              type: DamageType, incoming: Double, at t: Double,
                              extraMultiplier: Double, event: DamageEventKind) -> Double {
        guard incoming > 0 else { return 0 }
        let multiplier = layerMultiplier(layerIndex: layerIndex, type: type, at: t, state: state)
            * max(0, extraMultiplier)
        let slot = type.index
        state.touched[layerIndex][segment][slot] = true
        guard multiplier > 1e-12 else { return 0 }

        var potential = incoming * multiplier
        // Standard NPC armor cannot reduce a positive individual damage type
        // below one point.  This floor is an armor rule, not a universal damage
        // floor, so it is deliberately limited to health damage that actually
        // traverses armor.
        let armorFloor = layerIndex == State.healthIndex
            && !Rules.bypassesArmor(type)
            && currentArmor(at: t, state: state) > 1e-12
        if armorFloor { potential = max(1, potential) }
        if layerIndex == State.healthIndex {
            switch event {
            case .direct:
                state.targetDirect[segment][slot] += potential
            case .status:
                state.targetDot[segment][slot] += potential
            }
        }
        let pool = max(0, state.pools[layerIndex])
        let dealt = min(potential, pool)
        state.byType[layerIndex][segment][slot] += dealt
        state.pools[layerIndex] = max(0, pool - dealt)

        if state.pools[layerIndex] <= 1e-9, pool > 1e-9 {
            if state.breakTimes[layerIndex] == nil { state.breakTimes[layerIndex] = t }
            if layerIndex == State.shieldIndex {
                state.shieldGateUntil = max(state.shieldGateUntil, t + Rules.enemyShieldGateDuration)
            }
            if layerIndex == State.overguardIndex || layerIndex == State.shieldIndex {
                triggerMagneticBreak(&state, maximumLayer: state.maxima[layerIndex], at: t)
            }
        }

        guard potential > dealt + 1e-12 else { return 0 }
        return (potential - dealt) / multiplier
    }

    /// A layer break consumes no Magnetic stack.  It creates the documented
    /// forced Electricity status from every currently active Magnetic source;
    /// splitting by source preserves the same total 3% × stack count while
    /// retaining the source's own element/status/faction/duration modifiers.
    private func triggerMagneticBreak(_ state: inout State, maximumLayer: Double, at t: Double) {
        guard maximumLayer > 1e-12 else { return }
        var remainingStacks = 10.0
        for entry in state.magneticStacks where entry.expiry > t + 1e-9 && remainingStacks > 1e-12 {
            let weight = min(max(0, entry.weight), remainingStacks)
            guard weight > 1e-12 else { continue }
            appendMagneticBreakTesla(&state, baseTotal: 0.03 * maximumLayer * weight,
                                     source: entry.source, at: t)
            remainingStacks -= weight
        }
    }

    private func layerMultiplier(layerIndex: Int, type: DamageType, at t: Double, state: State) -> Double {
        let layer = Self.damageLayers[layerIndex]
        var multiplier = max(0, 1 - enemy.innateDR(layer))
        switch layer {
        case .overguard:
            if type == .void { multiplier *= 1.5 }
            multiplier *= Rules.magneticMultiplier(stacks: stackCount(.disrupt, at: t, state: state))
        case .shield:
            multiplier *= Rules.magneticMultiplier(stacks: stackCount(.disrupt, at: t, state: state))
        case .health:
            if !Rules.bypassesArmor(type) {
                multiplier *= 1 - Rules.enemyArmorDR(netArmor: currentArmor(at: t, state: state))
            }
            multiplier *= Rules.viralMultiplier(stacks: stackCount(.virus, at: t, state: state))
        case .armor:
            // Armor is a statistic, never a routed damage pool.
            multiplier = 0
        }
        return max(0, multiplier)
    }

    // MARK: - Statuses and DOTs

    private func spawn(kind: ProcKind, type: DamageType, count: Double,
                       presenceProbability: Double, seed: Double, at t: Double,
                       segment: Int, state: inout State, runtimes: [SegmentRuntime]) {
        guard count > 1e-12, !isImmune(type, state: state) else { return }
        let cap = stackCap(kind: kind, state: state)
        // `procs` reports events that occurred; reaching a stack cap replaces
        // the oldest active instance instead of making the event disappear.
        state.procCounts[segment][kind.rawValue, default: 0] += count
        let storedCount = cap.isFinite ? min(count, cap) : count
        guard storedCount > 1e-12 else { return }

        let attack = runtimes[segment]
        addStatusPresence(&state, kind: kind, probability: presenceProbability,
                          expiry: t + max(0, attack.statusDuration))
        if kind == .ignite {
            appendHeat(&state, count: storedCount, seed: seed, at: t, segment: segment, attack: attack, cap: cap)
            return
        }

        if kind == .tesla {
            appendTesla(&state, count: storedCount, seed: seed, at: t, segment: segment,
                        attack: attack, cap: cap)
            return
        }

        if kind == .gasCloud {
            appendGas(&state, count: storedCount, seed: seed, at: t, segment: segment,
                      attack: attack, cap: cap)
            return
        }

        if kind.isDamageOverTime {
            makeRoomForDots(&state, kind: kind, inserting: storedCount, cap: cap)
            let perTick = dotPerTick(kind: kind, attack: attack, seed: seed)
            let ticks = max(1, Int(attack.statusDuration.rounded(.down)))
            let routingType = dotType(kind: kind, source: type)
            appendDots(&state, kind: kind, type: routingType, modifierType: routingType,
                       count: storedCount, perTick: perTick, at: t, ticks: ticks, segment: segment)
            return
        }

        if kind == .detonate {
            makeRoomForDots(&state, kind: kind, inserting: storedCount, cap: cap)
            let statusMultiplier = attack.statusDamage
            let perTick = Rules.f32(Rules.f32(seed * attack.factionMultiplier)
                                    * Rules.blastRatio * statusMultiplier * attack.factionMultiplier)
            let fuse = Rules.blastFuse * max(attack.statusDuration, 0) / Rules.statusBaseDuration
            appendDots(&state, kind: kind, type: .blast, modifierType: .blast,
                       count: storedCount, perTick: perTick, at: t,
                       ticks: 1, segment: segment, firstTickDelay: max(0, fuse))
            if cap.isFinite && activeDotWeight(kind: kind, state: state) >= cap - 1e-9 {
                detonateBlasts(&state, at: t)
            }
            return
        }

        if kind == .disrupt {
            insertMagneticStacks(&state, count: storedCount, expiry: t + attack.statusDuration,
                                 at: t, cap: cap, source: MagneticSource(
                                    segment: segment,
                                    electricityElementBonus: attack.dotElementBonuses[.electricity] ?? 0,
                                    electricityStatusMultiplier: attack.statusDamage
                                        + (attack.dotStatusBonuses[.electricity] ?? 0),
                                    factionMultiplier: attack.factionMultiplier,
                                    statusDuration: max(0, attack.statusDuration)
                                 ))
            return
        }

        insertStacks(&state, kind: kind, count: storedCount,
                     expiry: t + attack.statusDuration, cap: cap, at: t)
    }

    /// Add one independent chance that a status type remains present until the
    /// supplied expiry.  Multiple entries compose as P(any) = 1 - Π(1 - p).
    private func addStatusPresence(_ state: inout State, kind: ProcKind,
                                   probability: Double, expiry: Double) {
        let p = min(max(probability, 0), 1)
        guard p > 1e-12 else { return }
        var entries = state.statusPresence[kind, default: []]
        entries.append(PresenceEntry(expiry: expiry, probability: p))
        state.statusPresence[kind] = entries
    }

    private func stackCap(kind: ProcKind, state: State) -> Double {
        // 翠绿执政官石修改的是腐蚀状态的层数上限，而不是护甲公式本身。
        // 目标自己的有限状态上限也随之增加；其它状态仍保持目标原始限制。
        let enemyCap = enemy.enemy.maxProcStacks ?? .infinity
        let baseCap = min(Rules.maxStacks(kind), enemyCap)
        var cap = kind == .corrosion
            ? baseCap + max(0, options.corrosiveStackCapBonus + resolvedCorrosiveStackCapBonus)
            : baseCap
        // Enemy Overguard rejects Radiation and limits Cold to four stacks;
        // it does not erase damaging statuses or Magnetic.
        if state.pools[State.overguardIndex] > 1e-9, kind == .freeze {
            cap = min(cap, 4)
        }
        return max(0, cap)
    }

    /// Statuses supplied by the surrounding loadout already exist when the
    /// first weapon projectile lands. They have no attributed DoT source here;
    /// this only installs their documented target-side effects and their
    /// Galvanized-Shot presence. A caller that needs an external DoT's damage
    /// must model that damage source explicitly rather than inventing this
    /// weapon's seed for it.
    private func seedInitialStatusStacks(_ state: inout State) {
        struct InitialEntry {
            let kind: ProcKind
            let count: Double
            let expiry: Double
            let heatArmorElapsed: Double
        }
        var entries: [InitialEntry] = []
        // The legacy viral field is the same shorthand as initialStatusStacks:
        // a status already present at t=0, with the ordinary six-second
        // remaining lifetime rather than an infinite hidden buff.
        if options.externalViralStacks > 0 {
            entries.append(InitialEntry(kind: .virus,
                                        count: options.externalViralStacks,
                                        expiry: Rules.statusBaseDuration,
                                        heatArmorElapsed: 0))
        }
        for (raw, count) in options.environment.initialStatusStacks {
            guard let kind = procKind(forExternalStatusName: raw), count > 0 else { continue }
            entries.append(InitialEntry(kind: kind, count: count,
                                        expiry: Rules.statusBaseDuration,
                                        heatArmorElapsed: 0))
        }
        for status in options.environment.initialStatuses {
            guard let kind = procKind(forExternalStatusName: status.type), status.stacks > 0 else { continue }
            entries.append(InitialEntry(kind: kind, count: status.stacks,
                                        expiry: max(0, status.remainingDuration),
                                        heatArmorElapsed: max(0, status.heatArmorElapsed)))
        }

        for entry in entries {
            let kind = entry.kind
            let requested = entry.count
            guard entry.expiry > 1e-12, requested > 1e-12 else { continue }
            let cap = stackCap(kind: kind, state: state)
            let count = cap.isFinite ? min(requested, cap) : requested
            guard count > 1e-12 else { continue }
            addStatusPresence(&state, kind: kind, probability: 1, expiry: entry.expiry)

            switch kind {
            case .disrupt:
                // Its break Electricity has no weapon-owned source in this
                // input path, but the stack's Shield/Overguard multiplier is
                // still part of the target state.
                let source = MagneticSource(segment: 0, electricityElementBonus: 0,
                                            electricityStatusMultiplier: 1,
                                            factionMultiplier: 1, statusDuration: entry.expiry)
                insertMagneticStacks(&state, count: count, expiry: entry.expiry,
                                     at: 0, cap: cap, source: source)
            case .ignite:
                // A detailed Heat entry provides the one missing datum bare
                // stacks cannot infer: how far its shared armor-strip ramp has
                // progressed. It still does not invent an external Heat DOT.
                let candidate = HeatArmorState(startedAt: -entry.heatArmorElapsed,
                                                activeUntil: entry.expiry,
                                                rampStep: Rules.heatArmorStripStep)
                if let existing = state.heatArmor {
                    state.heatArmor = HeatArmorState(
                        startedAt: min(existing.startedAt, candidate.startedAt),
                        activeUntil: max(existing.activeUntil, candidate.activeUntil),
                        rampStep: candidate.rampStep
                    )
                } else {
                    state.heatArmor = candidate
                }
            case .bleed, .poison, .tesla, .gasCloud:
                // Presence was installed above. The external DOT's seed and
                // source multipliers are not implied by a target status.
                break
            default:
                insertStacks(&state, kind: kind, count: count, expiry: entry.expiry,
                             cap: cap, at: 0)
            }
        }
    }

    private func procKind(forExternalStatusName raw: String) -> ProcKind? {
        if let type = DamageType(dataKey: raw), let kind = ProcKind(damageType: type) {
            return kind
        }
        switch raw.lowercased().filter({ $0.isLetter || $0.isNumber }) {
        case "bleed": return .bleed
        case "ignite": return .ignite
        case "poison": return .poison
        case "tesla": return .tesla
        case "gascloud": return .gasCloud
        case "detonate": return .detonate
        case "corrosion": return .corrosion
        case "virus": return .virus
        case "disrupt": return .disrupt
        case "freeze": return .freeze
        case "weakened": return .weakened
        case "knockback": return .knockback
        case "confusion": return .confusion
        default: return nil
        }
    }

    /// At a finite cap, a new status replaces the oldest active status.  The
    /// state stores fractional weights for analytic expected proc counts, so an
    /// eviction may split one weighted entry.
    private func insertStacks(_ state: inout State, kind: ProcKind, count: Double,
                              expiry: Double, cap: Double, at t: Double) {
        var entries = state.stacks[kind, default: []].filter { $0.expiry > t + 1e-9 }
        if cap.isFinite {
            var excess = max(0, entries.reduce(0) { $0 + $1.weight } + count - cap)
            while excess > 1e-12, let oldest = entries.indices.min(by: { entries[$0].expiry < entries[$1].expiry }) {
                let removed = min(entries[oldest].weight, excess)
                entries[oldest].weight -= removed
                excess -= removed
                if entries[oldest].weight <= 1e-12 { entries.remove(at: oldest) }
            }
        }
        entries.append(StackEntry(expiry: expiry, weight: count))
        state.stacks[kind] = entries
    }

    private func activeDotWeight(kind: ProcKind, state: State) -> Double {
        state.dots.reduce(0) { $0 + ($1.kind == kind ? $1.weight : 0) }
    }

    private func makeRoomForDots(_ state: inout State, kind: ProcKind, inserting: Double, cap: Double) {
        guard cap.isFinite else { return }
        var excess = max(0, activeDotWeight(kind: kind, state: state) + inserting - cap)
        while excess > 1e-12,
              let oldest = state.dots.indices.filter({ state.dots[$0].kind == kind })
                .min(by: { state.dots[$0].start < state.dots[$1].start }) {
            let removed = min(state.dots[oldest].weight, excess)
            state.dots[oldest].weight -= removed
            excess -= removed
            if state.dots[oldest].weight <= 1e-12 { state.dots.remove(at: oldest) }
        }
    }

    private func appendHeat(_ state: inout State, count: Double, seed: Double, at t: Double,
                            segment: Int, attack: SegmentRuntime, cap: Double) {
        let element = attack.dotElementBonuses[.heat] ?? 0
        let status = attack.statusDamage + (attack.dotStatusBonuses[.heat] ?? 0)
        let duration = max(0, attack.statusDuration)
        if var heat = state.heatDot, t <= heat.activeUntil + 1e-9 {
            // Later Heat contributions inherit the first Heat/Faction modifier
            // context.  Status-damage modifiers remain source-specific.
            let normalizedSeed = Rules.f32(seed * attack.factionMultiplier * status
                                           / max(heat.firstStatusMultiplier, 1e-12))
            replaceOldestHeatContributions(&heat.contributions, inserting: count, cap: cap)
            heat.contributions.append(HeatContribution(normalizedSeed: normalizedSeed,
                                                       weight: count,
                                                       segment: segment,
                                                       startedAt: t))
            heat.activeUntil = max(heat.activeUntil, t + duration)
            state.heatDot = heat
        } else {
            // The first source establishes Heat/Faction inheritance.  Its
            // status multiplier is intentionally kept outside the stored seed
            // so the exact tick-group `+1` is included once.
            let normalizedSeed = Rules.f32(seed * attack.factionMultiplier)
            state.heatDot = HeatDotState(contributions: [HeatContribution(normalizedSeed: normalizedSeed,
                                                                            weight: count,
                                                                            segment: segment,
                                                                            startedAt: t)],
                                         firstSegment: segment,
                                         firstElementBonus: element,
                                         firstFactionMultiplier: attack.factionMultiplier,
                                         firstStatusMultiplier: status,
                                         nextTick: t + Rules.dotFirstTickDelay(.ignite),
                                         activeUntil: t + duration)
        }

        let rampStep = Rules.heatArmorStripStep * duration / Rules.statusBaseDuration
        if let heat = state.heatArmor, t <= heat.activeUntil + 1e-9 {
            state.heatArmor?.activeUntil = max(heat.activeUntil, t + duration)
        } else {
            state.heatArmor = HeatArmorState(startedAt: t,
                                              activeUntil: t + duration,
                                              rampStep: max(rampStep, 1e-9))
        }
    }

    /// Insert ordinary Electricity into the tick group that begins on this
    /// pulse.  Its six-second lifetime remains per contribution; only the
    /// accumulator and displayed hit are shared by equal-time contributions.
    private func appendTesla(_ state: inout State, count: Double, seed: Double, at t: Double,
                             segment: Int, attack: SegmentRuntime, cap: Double) {
        let element = attack.dotElementBonuses[.electricity] ?? 0
        let status = attack.statusDamage + (attack.dotStatusBonuses[.electricity] ?? 0)
        let duration = max(0, attack.statusDuration)
        makeRoomForTesla(&state, inserting: count, cap: cap, at: t)

        if let index = state.teslaDots.firstIndex(where: { abs($0.nextTick - t) <= 1e-9 }) {
            var tesla = state.teslaDots[index]
            let hasOrdinaryContribution = tesla.contributions.contains { $0.usesAccumulator }
            let normalizedSeed: Double
            if hasOrdinaryContribution {
                // Preserve a later source's status-damage multiplier while the
                // pulse's first ordinary source retains its shared context.
                normalizedSeed = Rules.f32(seed * attack.factionMultiplier * status
                                            / max(tesla.firstStatusMultiplier, 1e-12))
            } else {
                tesla.firstSegment = segment
                tesla.firstElementBonus = element
                tesla.firstFactionMultiplier = attack.factionMultiplier
                tesla.firstStatusMultiplier = status
                normalizedSeed = Rules.f32(seed * attack.factionMultiplier)
            }
            tesla.contributions.append(TeslaContribution(normalizedSeed: normalizedSeed,
                                                          fixedPerTick: 0,
                                                          usesAccumulator: true,
                                                          weight: count,
                                                          segment: segment,
                                                          startedAt: t,
                                                          activeUntil: t + duration))
            state.teslaDots[index] = tesla
            return
        }

        state.teslaDots.append(TeslaDotState(
            contributions: [TeslaContribution(normalizedSeed: Rules.f32(seed * attack.factionMultiplier),
                                               fixedPerTick: 0,
                                               usesAccumulator: true,
                                               weight: count,
                                               segment: segment,
                                               startedAt: t,
                                               activeUntil: t + duration)],
            firstSegment: segment,
            firstElementBonus: element,
            firstFactionMultiplier: attack.factionMultiplier,
            firstStatusMultiplier: status,
            nextTick: t
        ))
    }

    /// Magnetic's documented break proc has a prescribed *total* damage
    /// rather than the weapon-DoT seed.  It still becomes an Electricity status
    /// event (and therefore shares a same-pulse display/tick group), but does
    /// not invent another accumulator `+1`.
    private func appendMagneticBreakTesla(_ state: inout State, baseTotal: Double,
                                          source: MagneticSource, at t: Double) {
        let duration = max(0, source.statusDuration)
        guard duration > 1e-12, baseTotal > 1e-12 else { return }
        let ticks = max(1, Int(duration.rounded(.down)))

        // Wiki: Electric damage mods apply normally; status-damage and faction
        // bonuses each apply twice; duration is a final multiplier to total.
        var total = Rules.f32(baseTotal)
        total = Rules.f32(total * (1 + source.electricityElementBonus))
        total = Rules.f32(total * source.electricityStatusMultiplier)
        total = Rules.f32(total * source.electricityStatusMultiplier)
        total = Rules.f32(total * source.factionMultiplier)
        total = Rules.f32(total * source.factionMultiplier)
        total = Rules.f32(total * duration / Rules.statusBaseDuration)
        let perTick = Rules.f32(total / Double(ticks))

        let cap = stackCap(kind: .tesla, state: state)
        makeRoomForTesla(&state, inserting: 1, cap: cap, at: t)
        state.procCounts[source.segment][ProcKind.tesla.rawValue, default: 0] += 1
        let contribution = TeslaContribution(normalizedSeed: 0,
                                             fixedPerTick: perTick,
                                             usesAccumulator: false,
                                             weight: 1,
                                             segment: source.segment,
                                             startedAt: t,
                                             activeUntil: t + duration)
        if let index = state.teslaDots.firstIndex(where: { abs($0.nextTick - t) <= 1e-9 }) {
            state.teslaDots[index].contributions.append(contribution)
        } else {
            state.teslaDots.append(TeslaDotState(contributions: [contribution],
                                                  firstSegment: source.segment,
                                                  firstElementBonus: 0,
                                                  firstFactionMultiplier: 1,
                                                  firstStatusMultiplier: 1,
                                                  nextTick: t))
        }
    }

    /// Gas uses the same f32 tick-group accumulator as the documented
    /// nine-stack example.  Its group is scoped to a pulse, while its members
    /// retain their independent status timers and the normal ten-stack cap.
    private func appendGas(_ state: inout State, count: Double, seed: Double, at t: Double,
                           segment: Int, attack: SegmentRuntime, cap: Double) {
        let element = attack.dotElementBonuses[.gas] ?? 0
        let status = attack.statusDamage + (attack.dotStatusBonuses[.gas] ?? 0)
        let duration = max(0, attack.statusDuration)
        makeRoomForGas(&state, inserting: count, cap: cap, at: t)

        if let index = state.gasDots.firstIndex(where: { abs($0.nextTick - t) <= 1e-9 }) {
            var gas = state.gasDots[index]
            let normalizedSeed = Rules.f32(seed * attack.factionMultiplier * status
                                           / max(gas.firstStatusMultiplier, 1e-12))
            gas.contributions.append(GasContribution(normalizedSeed: normalizedSeed,
                                                      weight: count,
                                                      segment: segment,
                                                      startedAt: t,
                                                      activeUntil: t + duration))
            state.gasDots[index] = gas
            return
        }

        state.gasDots.append(GasDotState(
            contributions: [GasContribution(normalizedSeed: Rules.f32(seed * attack.factionMultiplier),
                                             weight: count,
                                             segment: segment,
                                             startedAt: t,
                                             activeUntil: t + duration)],
            firstSegment: segment,
            firstElementBonus: element,
            firstFactionMultiplier: attack.factionMultiplier,
            firstStatusMultiplier: status,
            nextTick: t
        ))
    }

    private func activeTeslaWeight(state: State, at t: Double) -> Double {
        state.teslaDots.reduce(0) { total, group in
            total + group.contributions.reduce(0) { partial, contribution in
                partial + (contribution.activeUntil > t + 1e-9 ? contribution.weight : 0)
            }
        }
    }

    /// Finite enemy proc caps replace the oldest active Electricity
    /// contribution.  It is deliberately separate from `dots`: Tesla pulse
    /// groups carry per-contribution lifetimes rather than one shared timer.
    private func makeRoomForTesla(_ state: inout State, inserting: Double,
                                  cap: Double, at t: Double) {
        guard cap.isFinite else { return }
        var excess = max(0, activeTeslaWeight(state: state, at: t) + inserting - cap)
        while excess > 1e-12 {
            var oldest: (group: Int, contribution: Int)?
            for groupIndex in state.teslaDots.indices {
                for contributionIndex in state.teslaDots[groupIndex].contributions.indices {
                    let contribution = state.teslaDots[groupIndex].contributions[contributionIndex]
                    guard contribution.activeUntil > t + 1e-9 else { continue }
                    if let current = oldest {
                        let incumbent = state.teslaDots[current.group].contributions[current.contribution]
                        if contribution.startedAt < incumbent.startedAt {
                            oldest = (groupIndex, contributionIndex)
                        }
                    } else {
                        oldest = (groupIndex, contributionIndex)
                    }
                }
            }
            guard let oldest else { break }
            let removed = min(state.teslaDots[oldest.group].contributions[oldest.contribution].weight, excess)
            state.teslaDots[oldest.group].contributions[oldest.contribution].weight -= removed
            excess -= removed
            if state.teslaDots[oldest.group].contributions[oldest.contribution].weight <= 1e-12 {
                state.teslaDots[oldest.group].contributions.remove(at: oldest.contribution)
                if state.teslaDots[oldest.group].contributions.isEmpty {
                    state.teslaDots.remove(at: oldest.group)
                }
            }
        }
    }

    private func activeGasWeight(state: State, at t: Double) -> Double {
        state.gasDots.reduce(0) { total, group in
            total + group.contributions.reduce(0) { partial, contribution in
                partial + (contribution.activeUntil > t + 1e-9 ? contribution.weight : 0)
            }
        }
    }

    private func makeRoomForGas(_ state: inout State, inserting: Double,
                                 cap: Double, at t: Double) {
        guard cap.isFinite else { return }
        var excess = max(0, activeGasWeight(state: state, at: t) + inserting - cap)
        while excess > 1e-12 {
            var oldest: (group: Int, contribution: Int)?
            for groupIndex in state.gasDots.indices {
                for contributionIndex in state.gasDots[groupIndex].contributions.indices {
                    let contribution = state.gasDots[groupIndex].contributions[contributionIndex]
                    guard contribution.activeUntil > t + 1e-9 else { continue }
                    if let current = oldest {
                        let incumbent = state.gasDots[current.group].contributions[current.contribution]
                        if contribution.startedAt < incumbent.startedAt {
                            oldest = (groupIndex, contributionIndex)
                        }
                    } else {
                        oldest = (groupIndex, contributionIndex)
                    }
                }
            }
            guard let oldest else { break }
            let removed = min(state.gasDots[oldest.group].contributions[oldest.contribution].weight, excess)
            state.gasDots[oldest.group].contributions[oldest.contribution].weight -= removed
            excess -= removed
            if state.gasDots[oldest.group].contributions[oldest.contribution].weight <= 1e-12 {
                state.gasDots[oldest.group].contributions.remove(at: oldest.contribution)
                if state.gasDots[oldest.group].contributions.isEmpty {
                    state.gasDots.remove(at: oldest.group)
                }
            }
        }
    }

    private func insertMagneticStacks(_ state: inout State, count: Double, expiry: Double,
                                      at t: Double, cap: Double, source: MagneticSource) {
        var entries = state.magneticStacks.filter { $0.expiry > t + 1e-9 }
        if cap.isFinite {
            var excess = max(0, entries.reduce(0) { $0 + $1.weight } + count - cap)
            while excess > 1e-12,
                  let oldest = entries.indices.min(by: { entries[$0].startedAt < entries[$1].startedAt }) {
                let removed = min(entries[oldest].weight, excess)
                entries[oldest].weight -= removed
                excess -= removed
                if entries[oldest].weight <= 1e-12 { entries.remove(at: oldest) }
            }
        }
        entries.append(MagneticStackEntry(expiry: expiry, weight: count,
                                          startedAt: t, source: source))
        state.magneticStacks = entries
    }

    private func replaceOldestHeatContributions(_ contributions: inout [HeatContribution],
                                                inserting: Double, cap: Double) {
        guard cap.isFinite else { return }
        var excess = max(0, contributions.reduce(0) { $0 + $1.weight } + inserting - cap)
        while excess > 1e-12,
              let oldest = contributions.indices.min(by: { contributions[$0].startedAt < contributions[$1].startedAt }) {
            let removed = min(contributions[oldest].weight, excess)
            contributions[oldest].weight -= removed
            excess -= removed
            if contributions[oldest].weight <= 1e-12 { contributions.remove(at: oldest) }
        }
    }

    private func appendDots(_ state: inout State, kind: ProcKind, type: DamageType,
                            modifierType: DamageType,
                            count: Double, perTick: Double, at t: Double,
                            ticks: Int, segment: Int,
                            firstTickDelay: Double? = nil,
                            preMitigatedToxin: Bool = false) {
        let tickDelay = firstTickDelay ?? Rules.dotFirstTickDelay(kind)
        var remaining = count
        while remaining >= 1 - 1e-9 {
            state.dots.append(DotInstance(kind: kind, type: type, modifierType: modifierType,
                                           perTick: perTick, weight: 1, start: t,
                                           nextTick: t + tickDelay,
                                           ticksLeft: ticks, segment: segment,
                                           preMitigatedToxin: preMitigatedToxin))
            remaining -= 1
        }
        if remaining > 1e-9 {
            state.dots.append(DotInstance(kind: kind, type: type, modifierType: modifierType,
                                           perTick: perTick, weight: remaining, start: t,
                                           nextTick: t + tickDelay,
                                           ticksLeft: ticks, segment: segment,
                                           preMitigatedToxin: preMitigatedToxin))
        }
    }

    private func tickDots(_ state: inout State, at t: Double) {
        tickHeat(&state, at: t)
        tickTesla(&state, at: t)
        tickGas(&state, at: t)
        var index = 0
        while index < state.dots.count {
            guard state.dots[index].nextTick <= t + 1e-9 else {
                index += 1
                continue
            }
            let instance = state.dots[index]
            guard state.isAlive else { break }
            let tickDamage = instance.perTick * instance.weight
            state.rawDot[instance.segment][instance.type.index] += tickDamage
            if instance.preMitigatedToxin {
                routePreMitigatedToxin(&state, segment: instance.segment, incoming: tickDamage,
                                        at: t, event: .status)
            } else {
                let incoming = tickDamage
                    * faction.multiplier(for: instance.modifierType)
                    * enemy.elementalResistance(instance.modifierType)
                    * (1 - enemy.statusDR)
                route(&state, segment: instance.segment, type: instance.type, incoming: incoming,
                      at: t, event: .status)
            }

            var next = instance
            next.ticksLeft -= 1
            if next.ticksLeft <= 0 {
                state.dots.remove(at: index)
            } else {
                next.nextTick += Rules.statusTickInterval
                state.dots[index] = next
                index += 1
            }
        }
    }

    private func tickHeat(_ state: inout State, at t: Double) {
        guard var heat = state.heatDot,
              heat.nextTick <= t + 1e-9 else { return }
        guard heat.nextTick <= heat.activeUntil + 1e-9 else {
            state.heatDot = nil
            return
        }

        // `(sum(seed) + 1)` is one accumulator for the entire Heat tick group,
        // not one bonus per Heat stack.  Each displayed intermediate is f32.
        let seedTotal = heat.contributions.reduce(0) {
            Rules.f32($0 + Rules.f32($1.normalizedSeed * $1.weight))
        }
        var seedsBySegment: [Int: Double] = [:]
        for contribution in heat.contributions {
            seedsBySegment[contribution.segment, default: 0] = Rules.f32(
                (seedsBySegment[contribution.segment] ?? 0)
                    + Rules.f32(contribution.normalizedSeed * contribution.weight)
            )
        }

        var perTick = Rules.f32(seedTotal + 1)
        perTick = Rules.f32(perTick * Rules.dotRatio(.ignite))
        perTick = Rules.f32(perTick * (1 + heat.firstElementBonus))
        perTick = Rules.f32(perTick * heat.firstStatusMultiplier)
        perTick = Rules.f32(perTick * heat.firstFactionMultiplier)

        let total = max(seedTotal + 1, 1e-12)
        for segment in seedsBySegment.keys.sorted() where state.isAlive {
            let seed = seedsBySegment[segment] ?? 0
            let share = (seed + (segment == heat.firstSegment ? 1 : 0)) / total
            let tickDamage = perTick * share
            state.rawDot[segment][DamageType.heat.index] += tickDamage
            let incoming = tickDamage
                * faction.multiplier(for: .heat)
                * enemy.elementalResistance(.heat)
                * (1 - enemy.statusDR)
            route(&state, segment: segment, type: .heat, incoming: incoming, at: t, event: .status)
        }

        heat.nextTick += Rules.statusTickInterval
        state.heatDot = heat.nextTick <= heat.activeUntil + 1e-9 ? heat : nil
    }

    private func tickTesla(_ state: inout State, at t: Double) {
        var index = 0
        while index < state.teslaDots.count {
            guard state.teslaDots[index].nextTick <= t + 1e-9 else {
                index += 1
                continue
            }
            guard state.isAlive else { break }

            var tesla = state.teslaDots[index]
            let active = tesla.contributions.filter {
                $0.weight > 1e-12 && $0.activeUntil > t + 1e-9
            }
            guard !active.isEmpty else {
                state.teslaDots.remove(at: index)
                continue
            }

            let ordinary = active.filter(\.usesAccumulator)
            var damageBySegment: [Int: Double] = [:]
            if !ordinary.isEmpty {
                // One `+1` for all ordinary Electricity contributions that
                // occur in this pulse, exactly as the damage calculation
                // formula specifies.  Keep every intermediate binary32.
                let seedTotal = ordinary.reduce(0.0) {
                    Rules.f32($0 + Rules.f32($1.normalizedSeed * $1.weight))
                }
                var seedsBySegment: [Int: Double] = [:]
                for contribution in ordinary {
                    seedsBySegment[contribution.segment, default: 0] = Rules.f32(
                        (seedsBySegment[contribution.segment] ?? 0)
                            + Rules.f32(contribution.normalizedSeed * contribution.weight)
                    )
                }

                var pulseDamage = Rules.f32(seedTotal + 1)
                pulseDamage = Rules.f32(pulseDamage * Rules.dotRatio(.tesla))
                pulseDamage = Rules.f32(pulseDamage * (1 + tesla.firstElementBonus))
                pulseDamage = Rules.f32(pulseDamage * tesla.firstStatusMultiplier)
                pulseDamage = Rules.f32(pulseDamage * tesla.firstFactionMultiplier)

                let accumulatorOwner = ordinary.first?.segment ?? tesla.firstSegment
                let total = max(seedTotal + 1, 1e-12)
                for segment in seedsBySegment.keys.sorted() {
                    let seed = seedsBySegment[segment] ?? 0
                    let share = (seed + (segment == accumulatorOwner ? 1 : 0)) / total
                    damageBySegment[segment, default: 0] += pulseDamage * share
                }
            }

            // Magnetic-break Electricity already has a prescribed per-tick
            // total.  It can share the pulse's display event but must not add a
            // second synthetic `+1` accumulator.
            for contribution in active where !contribution.usesAccumulator {
                damageBySegment[contribution.segment, default: 0] +=
                    contribution.fixedPerTick * contribution.weight
            }

            // Commit this group's next pulse before routing.  A Tesla tick can
            // itself break Magnetic-affected Shield/Overguard, which appends a
            // new forced Tesla at the current timestamp.  Writing the local
            // snapshot afterwards would otherwise erase that newly queued proc.
            tesla.contributions = active
            tesla.nextTick += Rules.statusTickInterval
            if tesla.contributions.contains(where: { $0.activeUntil > tesla.nextTick + 1e-9 }) {
                state.teslaDots[index] = tesla
            } else {
                state.teslaDots.remove(at: index)
            }

            for segment in damageBySegment.keys.sorted() where state.isAlive {
                let tickDamage = damageBySegment[segment] ?? 0
                guard tickDamage > 1e-12 else { continue }
                state.rawDot[segment][DamageType.electricity.index] += tickDamage
                let incoming = tickDamage
                    * faction.multiplier(for: .electricity)
                    * enemy.elementalResistance(.electricity)
                    * (1 - enemy.statusDR)
                route(&state, segment: segment, type: .electricity, incoming: incoming,
                      at: t, event: .status)
            }
        }
    }

    private func tickGas(_ state: inout State, at t: Double) {
        var index = 0
        while index < state.gasDots.count {
            guard state.gasDots[index].nextTick <= t + 1e-9 else {
                index += 1
                continue
            }
            guard state.isAlive else { break }

            var gas = state.gasDots[index]
            let active = gas.contributions.filter {
                $0.weight > 1e-12 && $0.activeUntil > t + 1e-9
            }
            guard !active.isEmpty else {
                state.gasDots.remove(at: index)
                continue
            }

            let seedTotal = active.reduce(0.0) {
                Rules.f32($0 + Rules.f32($1.normalizedSeed * $1.weight))
            }
            var seedsBySegment: [Int: Double] = [:]
            for contribution in active {
                seedsBySegment[contribution.segment, default: 0] = Rules.f32(
                    (seedsBySegment[contribution.segment] ?? 0)
                        + Rules.f32(contribution.normalizedSeed * contribution.weight)
                )
            }

            var pulseDamage = Rules.f32(seedTotal + 1)
            pulseDamage = Rules.f32(pulseDamage * Rules.dotRatio(.gasCloud))
            pulseDamage = Rules.f32(pulseDamage * (1 + gas.firstElementBonus))
            pulseDamage = Rules.f32(pulseDamage * gas.firstStatusMultiplier)
            pulseDamage = Rules.f32(pulseDamage * gas.firstFactionMultiplier)

            let total = max(seedTotal + 1, 1e-12)
            for segment in seedsBySegment.keys.sorted() where state.isAlive {
                let seed = seedsBySegment[segment] ?? 0
                let share = (seed + (segment == gas.firstSegment ? 1 : 0)) / total
                let tickDamage = pulseDamage * share
                state.rawDot[segment][DamageType.gas.index] += tickDamage
                let incoming = tickDamage
                    * faction.multiplier(for: .gas)
                    * enemy.elementalResistance(.gas)
                    * (1 - enemy.statusDR)
                route(&state, segment: segment, type: .gas, incoming: incoming,
                      at: t, event: .status)
            }

            gas.contributions = active
            gas.nextTick += Rules.statusTickInterval
            if gas.contributions.contains(where: { $0.activeUntil > gas.nextTick + 1e-9 }) {
                state.gasDots[index] = gas
                index += 1
            } else {
                state.gasDots.remove(at: index)
            }
        }
    }

    private func detonateBlasts(_ state: inout State, at t: Double) {
        var index = 0
        while index < state.dots.count {
            let instance = state.dots[index]
            guard instance.kind == .detonate else {
                index += 1
                continue
            }
            let damage = instance.perTick * instance.weight
            state.rawDot[instance.segment][instance.type.index] += damage
            let incoming = damage
                * faction.multiplier(for: instance.modifierType)
                * enemy.elementalResistance(instance.modifierType)
                * (1 - enemy.statusDR)
            route(&state, segment: instance.segment, type: instance.type, incoming: incoming,
                  at: t, event: .status)
            state.dots.remove(at: index)
        }
    }

    private func dotPerTick(kind: ProcKind, attack: SegmentRuntime, seed: Double) -> Double {
        let statusType: DamageType
        let elementalBonus: Double
        switch kind {
        case .bleed:
            statusType = .slash
            elementalBonus = 0
        case .ignite:
            statusType = .heat
            elementalBonus = attack.dotElementBonuses[.heat] ?? 0
        case .poison:
            statusType = .toxin
            elementalBonus = attack.dotElementBonuses[.toxin] ?? 0
        case .tesla:
            statusType = .electricity
            elementalBonus = attack.dotElementBonuses[.electricity] ?? 0
        case .gasCloud:
            statusType = .gas
            elementalBonus = attack.dotElementBonuses[.gas] ?? 0
        default:
            return 0
        }
        // Every independent Slash/Toxin stack has its own f32 seed accumulator
        // beginning at one.  Heat is handled separately above because all of
        // its active stacks are one shared tick group.
        let statusMultiplier = attack.statusDamage + (attack.dotStatusBonuses[statusType] ?? 0)
        var value = Rules.f32(Rules.f32(seed * attack.factionMultiplier) + 1)
        value = Rules.f32(value * Rules.dotRatio(kind))
        value = Rules.f32(value * (1 + elementalBonus))
        value = Rules.f32(value * statusMultiplier)
        return Rules.f32(value * attack.factionMultiplier)
    }

    private func dotType(kind: ProcKind, source: DamageType) -> DamageType {
        switch kind {
        case .bleed: return .cinematic
        case .ignite: return .heat
        case .poison: return .toxin
        case .tesla: return .electricity
        case .gasCloud: return .gas
        case .detonate: return .blast
        default: return source
        }
    }

    private func isImmune(_ type: DamageType, state: State) -> Bool {
        if enemy.enemy.statusImmune.contains("all") || enemy.enemy.statusImmune.contains(type.rawValue) {
            return true
        }
        // This is specifically enemy Eximus Overguard policy.  Do not apply the
        // player-Overguard blanket status immunity here.
        return state.pools[State.overguardIndex] > 1e-9 && type == .radiation
    }

    private func stackCount(_ kind: ProcKind, at t: Double, state: State) -> Double {
        if kind == .disrupt {
            return state.magneticStacks.reduce(0) { partial, entry in
                partial + (entry.expiry > t ? entry.weight : 0)
            }
        }
        return state.stacks[kind, default: []].reduce(0) { partial, entry in
            partial + (entry.expiry > t ? entry.weight : 0)
        }
    }

    /// Cold's weapon-hit critical-damage bonus: 0.10x at one stack, +0.05x
    /// for stacks 2...9, then +1.0x at the ten-stack Frozen state.
    /// Source: <https://wiki.warframe.com/w/Damage/Cold_Damage>
    private static func coldCriticalDamageBonus(stacks: Double) -> Double {
        let n = min(max(stacks, 0), 10)
        guard n > 0 else { return 0 }
        if n >= 10 { return 1.0 }
        return 0.10 + 0.05 * (n - 1)
    }

    private func currentArmor(at t: Double, state: State) -> Double {
        var armor = enemy.armor * (1 - min(max(options.armorStrip, 0), 1))
        armor *= Rules.corrosiveArmorFactor(stacks: stackCount(.corrosion, at: t, state: state))
        armor *= 1 - heatArmorStrip(at: t, state: state)
        return max(0, armor)
    }

    private func heatArmorStrip(at t: Double, state: State) -> Double {
        guard let heat = state.heatArmor else { return 0 }
        if t <= heat.activeUntil + 1e-9 {
            let elapsed = max(0, t - heat.startedAt)
            let stage = min(4, Int(floor(elapsed / heat.rampStep + 1e-9)))
            return Rules.heatArmorStripStages[stage]
        }

        // When the last Heat proc ends, the game restores armor in the reverse
        // 50/40/30/15/0 sequence once every 1.5 seconds for six seconds.
        let fadeStage = min(4, Int(floor((t - heat.activeUntil)
                                          / Rules.heatArmorRecoveryStep + 1e-9)))
        return Rules.heatArmorStripStages[4 - fadeStage]
    }
}
