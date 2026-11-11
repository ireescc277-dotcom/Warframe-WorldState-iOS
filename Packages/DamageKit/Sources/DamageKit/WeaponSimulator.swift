import Foundation

/// 一组同时开火的攻击段在同一个敌人状态池上的模拟。
///
/// 口径见 README「计算口径」：
///  - 窗口 W 内按射速排出每发的时刻（含弹匣与换弹），逐发结算；
///  - 每段攻击独立成账，各自的 DPS / TTK；
///  - 同一次开火产生的多段（`comb`，例如直击 + 爆炸 + 毒云）**共享同一个状态池**，
///    所以 A 段挂上的病毒层数会抬高 B 段的伤害；
///  - 生命 / 护甲 / 护盾 / 超宏四层独立结算，互不相加。
///
/// 全程用期望值（暴击期望、期望触发数），没有任何随机抽样，
/// 因此同一输入必然得到完全相同的浮点结果。
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

    // MARK: - 对外

    private var runtimes: [SegmentRuntime] {
        segments.map { attack in
            let crit = Rules.expectedCritMultiplier(critChance: attack.critChance,
                                                    critDamage: attack.critMultiplier)
            return SegmentRuntime(
                name: attack.name,
                notes: attack.notes,
                damage: attack.orderedDamage,
                totalDamage: attack.totalDamage,
                // 每颗弹丸的系数：暴击期望 × 爆头 × (1+Bane)。多重单独乘，因为
                // 灵化的「弹匣最后一发 +3 多重」是逐发变化的。
                perPelletScale: crit * attack.headshotMultiplier * (1 + attack.factionBonus),
                critMultiplier: crit,
                multishot: attack.multishot,
                lastShotMultishot: attack.lastShotMultishot,
                statusChance: attack.statusChance,
                dotBase: attack.totalDamage * crit * attack.headshotMultiplier,
                factionSquared: (1 + attack.factionBonus) * (1 + attack.factionBonus),
                statusDamage: 1 + attack.statusDamageBonus,
                statusDuration: attack.statusDuration
            )
        }
    }

    public func run() -> [AttackResult] {
        let schedules = segments.map { shotSchedule(for: $0) }
        var layerOutcomes: [(Layer, LayerOutcome)] = []

        for layer in Layer.allCases {
            let hp = enemy.layerHP(layer)
            guard hp > 0 else { continue }
            layerOutcomes.append((layer, simulate(layer: layer, hp: hp, schedules: schedules)))
        }

        return segments.indices.map { index in
            var layers: [LayerResult] = []
            for (layer, outcome) in layerOutcomes {
                let hp = enemy.layerHP(layer)
                let damage = outcome.damage[index] ?? 0
                layers.append(LayerResult(layer: layer,
                                          maxHP: hp,
                                          damage: damage,
                                          dps: damage / max(options.window, 1e-9),
                                          ttk: outcome.ttk[index] ?? nil))
            }
            let raw = layerOutcomes.first(where: { $0.0 == .health })
                .map { $0.1.raw[index] ?? 0 } ?? 0
            let direct = layerOutcomes.first(where: { $0.0 == .health })
                .map { $0.1.direct[index] ?? 0 } ?? 0
            let dot = layerOutcomes.first(where: { $0.0 == .health })
                .map { $0.1.dot[index] ?? 0 } ?? 0
            let procs = layerOutcomes.first(where: { $0.0 == .health })
                .map { $0.1.procs[index] ?? [:] } ?? [:]

            return AttackResult(
                attack: segments[index].name,
                shots: Double(schedules[index].count),
                dps: raw / max(options.window, 1e-9),
                directDamage: direct,
                dotDamage: dot,
                layers: layers,
                procs: procs,
                notes: segments[index].notes
            )
        }
    }

    /// 一发子弹：开火时刻，以及它是否是弹匣里的最后一发。
    public struct Shot: Sendable, Equatable {
        public var time: Double
        public var isLastInMagazine: Bool

        public init(time: Double, isLastInMagazine: Bool) {
            self.time = time
            self.isLastInMagazine = isLastInMagazine
        }
    }

    /// 每发（含 burst 展开）的时刻。换弹真实占用时间。
    public func shotSchedule(for attack: ResolvedAttack) -> [Shot] {
        let rate = max(attack.fireRate, 1e-9)
        let interval = 1.0 / rate
        let mag = max(1, attack.magazine)
        let reload = max(0, attack.reload)
        let burst = max(1, attack.burstCount)
        let burstDelay = max(0, attack.burstDelay)

        var shots: [Shot] = []
        var t = 0.0
        var inMag: Double = 0
        var guardCount = 0

        while t < options.window - 1e-9 && guardCount < 200_000 {
            for b in 0..<burst {
                let shotTime = t + Double(b) * burstDelay
                if shotTime < options.window - 1e-9 {
                    // 弹匣序号从 1 数：正好等于 mag 的那一发就是最后一发。
                    let index = inMag + Double(b) + 1
                    shots.append(Shot(time: shotTime,
                                      isLastInMagazine: abs(index - mag) < 1e-9))
                }
            }
            inMag += Double(burst)
            // 弹匣打空后换弹；换弹时间为 0 时至少按一个射击间隔推进，
            // 否则周期为 0 会生成无限发。
            let step = inMag >= mag - 1e-9
                ? max(reload, interval * Double(burst))
                : interval * Double(burst)
            if inMag >= mag - 1e-9 { inMag = 0 }
            guardCount += 1
            guard step > 0 else { break }
            t += step
        }
        return shots.sorted { $0.time < $1.time }
    }

    // MARK: - 内部状态

    private struct StackEntry {
        var expiry: Double
        var weight: Double
    }

    private struct DotInstance {
        var kind: ProcKind
        var type: DamageType
        var perTick: Double
        var start: Double
        var nextTick: Double
        var ticksLeft: Int
        var segment: Int
    }

    /// 每段攻击里「不随时间变化」的量，开跑前算一次，避免每发重算和结构体拷贝。
    private struct SegmentRuntime {
        let name: String
        let notes: [String]
        let damage: [DamageEntry]
        let totalDamage: Double
        let perPelletScale: Double   // crit × 爆头 × (1+Bane)
        let critMultiplier: Double
        let multishot: Double
        let lastShotMultishot: Double // 弹匣最后一发额外多重
        let statusChance: Double      // 每弹丸
        let dotBase: Double        // 命中总伤害 × crit × 爆头
        let factionSquared: Double // (1+Bane)²
        let statusDamage: Double
        let statusDuration: Double

        func multishot(lastInMagazine: Bool) -> Double {
            lastInMagazine ? multishot + lastShotMultishot : multishot
        }
    }

    private struct State {
        var hp: Double
        var acc: [Int: Double] = [:]
        var ttk: [Int: Double?] = [:]
        var direct: [Int: Double] = [:]
        var dot: [Int: Double] = [:]
        var raw: [Int: Double] = [:]
        var procCounts: [Int: [String: Double]] = [:]
        var dots: [DotInstance] = []
        var stacks: [ProcKind: [StackEntry]] = [:]
    }

    private struct LayerOutcome {
        var damage: [Int: Double] = [:]
        var ttk: [Int: Double?] = [:]
        var direct: [Int: Double] = [:]
        var dot: [Int: Double] = [:]
        var raw: [Int: Double] = [:]
        var procs: [Int: [String: Double]] = [:]
    }

    // MARK: - 时间轴

    private func simulate(layer: Layer, hp: Double, schedules: [[Shot]]) -> LayerOutcome {
        let runtimes = self.runtimes
        var state = State(hp: hp)
        var pointers = [Int](repeating: 0, count: schedules.count)

        // 外部病毒层数（战甲技能 / 队友），在窗口开始时就已经挂在目标身上。
        let externalViral = min(max(options.externalViralStacks, 0), 10)
        if externalViral > 0 {
            state.stacks[.virus] = [StackEntry(expiry: .infinity, weight: externalViral)]
        }

        while true {
            var nextSegment = -1
            var nextShot = Double.infinity
            var nextIsLast = false
            for i in schedules.indices where pointers[i] < schedules[i].count {
                let shot = schedules[i][pointers[i]]
                if shot.time < nextShot {
                    nextShot = shot.time
                    nextIsLast = shot.isLastInMagazine
                    nextSegment = i
                }
            }
            var earliestDot = Double.infinity
            for dot in state.dots where dot.nextTick < earliestDot { earliestDot = dot.nextTick }
            let t = min(earliestDot, nextShot)
            // 严格小于窗口：正好落在 t=W 的那一发算在窗口外，
            // 这样 DPS 不会因为端点重复计数而超过「单发 × 射速」。
            if !(t < options.window - 1e-9) { break }

            if earliestDot <= nextShot {
                tickDots(&state, at: t, layer: layer, runtimes: runtimes)
            } else {
                fire(&state, segment: nextSegment, at: t, lastInMagazine: nextIsLast,
                     layer: layer, runtimes: runtimes)
                pointers[nextSegment] += 1
            }
        }

        var outcome = LayerOutcome()
        for i in segments.indices {
            let damage = state.acc[i] ?? 0
            outcome.damage[i] = damage
            outcome.ttk[i] = state.ttk[i] ?? nil
            outcome.direct[i] = state.direct[i] ?? 0
            outcome.dot[i] = state.dot[i] ?? 0
            outcome.raw[i] = state.raw[i] ?? 0
            outcome.procs[i] = state.procCounts[i] ?? [:]
        }
        return outcome
    }

    private func fire(_ state: inout State, segment index: Int, at t: Double,
                      lastInMagazine: Bool, layer: Layer,
                      runtimes: [SegmentRuntime]) {
        let attack = runtimes[index]
        let multishot = attack.multishot(lastInMagazine: lastInMagazine)
        let scale = attack.perPelletScale * multishot

        let context = mitigationContext(layer: layer, at: t, state: state)
        for entry in attack.damage {
            let type = entry.type
            var raw = entry.value * scale
            raw *= faction.multiplier(for: type) * enemy.elementalResistance(type)
            let dealt = raw * mitigation(layer: layer, type: type, context: context)
            state.raw[index, default: 0] += raw
            state.direct[index, default: 0] += raw
            apply(&state, index: index, dealt, at: t)
        }

        // 超宏在的时候敌人免疫状态；这一层只吃直伤。
        guard layer != .overguard else { return }
        let expectedProcs = attack.statusChance * multishot
        guard expectedProcs > 0 else { return }

        // 免疫的类型要从权重里剔除，剩下的重新归一化。
        // 来源：<https://wiki.warframe.com/w/Status_Effect>
        var weights: [(DamageType, ProcKind, Double)] = []
        var total = 0.0
        for entry in attack.damage {
            let type = entry.type
            guard let kind = ProcKind(damageType: type) else { continue }
            guard !isImmune(type) else { continue }
            guard entry.value > 0 else { continue }
            weights.append((type, kind, entry.value))
            total += entry.value
        }
        guard total > 0 else { return }

        for (type, kind, value) in weights {
            let count = expectedProcs * (value / total) * Rules.physicalProcWeight
            spawn(kind: kind, type: type, count: count, at: t,
                  segment: index, state: &state, layer: layer, runtimes: runtimes)
        }
    }

    private func spawn(kind: ProcKind, type: DamageType, count: Double, at t: Double,
                       segment: Int, state: inout State, layer: Layer,
                       runtimes: [SegmentRuntime]) {
        guard count > 0 else { return }
        let cap = min(Rules.maxStacks(kind), enemy.enemy.maxProcStacks ?? .infinity)
        let existing = stackCount(kind, at: t, state: state)
        guard existing < cap else { return }
        let allowed = min(count, cap - existing)
        guard allowed > 0 else { return }

        state.procCounts[segment, default: [:]][kind.rawValue, default: 0] += allowed

        if kind.isDamageOverTime {
            let perTick = dotPerTick(kind: kind, type: type, attack: runtimes[segment])
            let ticks = max(1, Int(runtimes[segment].statusDuration.rounded(.down)))
            var remaining = allowed
            // 整数层给完整实例（保证 tick 相位正确），小数层给一个按比例缩放的实例。
            while remaining >= 1 - 1e-9 {
                state.dots.append(DotInstance(kind: kind,
                                              type: dotType(kind: kind, source: type),
                                              perTick: perTick,
                                              start: t,
                                              nextTick: t + Rules.dotFirstTickDelay(kind),
                                              ticksLeft: ticks,
                                              segment: segment))
                remaining -= 1
            }
            if remaining > 1e-9 {
                state.dots.append(DotInstance(kind: kind,
                                              type: dotType(kind: kind, source: type),
                                              perTick: perTick * remaining,
                                              start: t,
                                              nextTick: t + Rules.dotFirstTickDelay(kind),
                                              ticksLeft: ticks,
                                              segment: segment))
            }
        } else if kind == .detonate {
            let attack = runtimes[segment]
            let perTick = attack.dotBase
                * Rules.blastRatio
                * attack.factionSquared
                * attack.statusDamage
                * faction.multiplier(for: .blast)
            state.dots.append(DotInstance(kind: kind, type: .blast,
                                          perTick: perTick * allowed,
                                          start: t,
                                          nextTick: t + Rules.blastFuse,
                                          ticksLeft: 1,
                                          segment: segment))
        } else {
            let duration: Double
            switch kind {
            case .corrosion: duration = 8.0
            default: duration = runtimes[segment].statusDuration
            }
            state.stacks[kind, default: []].append(StackEntry(expiry: t + duration, weight: allowed))
        }
    }

    /// 每跳伤害。
    ///
    /// 结构来自 wiki 的 Bleed 示例：
    /// `100 × (1+Serration) × 0.35 × (1+Bane)² × (1+Elementalist)`
    /// 即：命中总伤害 × 比例 × 派系加成**二次结算** × 状态伤害加成。
    /// 来源：<https://wiki.warframe.com/w/Status_Effect>（"DoT Damage Scaling"）
    private func dotPerTick(kind: ProcKind, type: DamageType, attack: SegmentRuntime) -> Double {
        let resolvedType = dotType(kind: kind, source: type)
        return attack.dotBase
            * Rules.dotRatio(kind)
            * attack.factionSquared
            * attack.statusDamage
            * faction.multiplier(for: resolvedType)
            * enemy.elementalResistance(resolvedType)
    }

    private func dotType(kind: ProcKind, source: DamageType) -> DamageType {
        switch kind {
        case .bleed: return .cinematic   // Cinematic 类型，无视护甲
        case .ignite: return .heat
        case .poison: return .toxin
        case .tesla: return .electricity
        case .gasCloud: return .gas
        case .detonate: return .blast
        default: return source
        }
    }

    private func isImmune(_ type: DamageType) -> Bool {
        if enemy.enemy.statusImmune.contains("all") { return true }
        return enemy.enemy.statusImmune.contains(type.rawValue)
    }

    private func tickDots(_ state: inout State, at t: Double, layer: Layer,
                          runtimes: [SegmentRuntime]) {
        var index = 0
        while index < state.dots.count {
            guard state.dots[index].nextTick <= t + 1e-9 else { index += 1; continue }
            var instance = state.dots[index]
            let raw = instance.perTick
            let dealt = raw * mitigation(layer: layer, type: instance.type,
                                         context: mitigationContext(layer: layer, at: t, state: state))
            state.raw[instance.segment, default: 0] += raw
            state.dot[instance.segment, default: 0] += raw
            apply(&state, index: instance.segment, dealt, at: t)

            instance.ticksLeft -= 1
            if instance.ticksLeft <= 0 {
                state.dots.remove(at: index)
            } else {
                instance.nextTick += Rules.statusTickInterval
                state.dots[index] = instance
                index += 1
            }
        }
    }

    private func apply(_ state: inout State, index: Int, _ amount: Double, at t: Double) {
        guard amount > 0 else { return }
        let total = (state.acc[index] ?? 0) + amount
        state.acc[index] = total
        if state.ttk[index] == nil, total >= state.hp {
            state.ttk[index] = t
        }
    }

    // MARK: - 减伤与状态

    private func stackCount(_ kind: ProcKind, at t: Double, state: State) -> Double {
        guard let entries = state.stacks[kind] else { return 0 }
        var total = 0.0
        for entry in entries where entry.expiry > t { total += entry.weight }
        return total
    }

    /// 同一时刻同一层的公共减伤系数，每发只算一次。
    private struct MitigationContext {
        var armorFactor: Double   // 1 - DR
        var innate: Double
        var viral: Double
        var magnetic: Double
    }

    private func mitigationContext(layer: Layer, at t: Double, state: State) -> MitigationContext {
        switch layer {
        case .health:
            let armorFactor = 1 - Rules.enemyArmorDR(netArmor: currentArmor(at: t, state: state))
            return MitigationContext(armorFactor: armorFactor,
                                     innate: 1 - enemy.innateDR(.health),
                                     viral: Rules.viralMultiplier(stacks: stackCount(.virus, at: t, state: state)),
                                     magnetic: 1)
        case .armor:
            // 护甲层是「护甲值池」，不吃护甲减伤（那会重复计算）。
            return MitigationContext(armorFactor: 1,
                                     innate: 1 - enemy.innateDR(.armor),
                                     viral: 1, magnetic: 1)
        case .shield:
            return MitigationContext(armorFactor: 1,
                                     innate: 1 - enemy.innateDR(.shield),
                                     viral: 1,
                                     magnetic: Rules.magneticMultiplier(stacks: stackCount(.disrupt, at: t, state: state)))
        case .overguard:
            return MitigationContext(armorFactor: 1, innate: 1, viral: 1, magnetic: 1)
        }
    }

    /// 只包含「该层自己的减伤」，不含派系易伤与 Bane —— 那些在调用处乘。
    private func mitigation(layer: Layer, type: DamageType, context: MitigationContext) -> Double {
        var m = context.innate
        switch layer {
        case .health:
            if !Rules.bypassesArmor(type) { m *= context.armorFactor }
            m *= context.viral
        case .armor:
            break
        case .shield:
            if Rules.bypassesShield(type) { return 0 }
            m *= context.magnetic
        case .overguard:
            break
        }
        return max(0, m)
    }

    private func currentArmor(at t: Double, state: State) -> Double {
        var armor = enemy.armor * (1 - min(max(options.armorStrip, 0), 1))
        armor *= Rules.corrosiveArmorFactor(stacks: stackCount(.corrosion, at: t, state: state))
        if let heatStart = earliestHeatStart(state: state) {
            let ramp = min(1, max(0, (t - heatStart) / Rules.heatArmorStripRamp))
            armor *= 1 - Rules.heatArmorStripMax * ramp
        }
        return max(0, armor)
    }

    private func earliestHeatStart(state: State) -> Double? {
        var earliest: Double?
        for dot in state.dots where dot.kind == .ignite {
            if earliest == nil || dot.start < earliest! { earliest = dot.start }
        }
        return earliest
    }
}
