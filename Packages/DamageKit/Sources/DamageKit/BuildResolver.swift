import Foundation

/// 一条伤害分量。用数组而不是字典，是为了让遍历顺序固定、也不必每发重建。
public struct DamageEntry: Sendable, Equatable {
    public let type: DamageType
    public let value: Double

    public init(type: DamageType, value: Double) {
        self.type = type
        self.value = value
    }
}

/// Charged attacks have a different firing cadence from ordinary shots.  The
/// category is derived from the weapon data rather than a weapon-name list:
/// bows use charge-time plus reload-time, while other charge triggers use
/// charge-time plus the normal shot delay.
public enum ChargeTiming: Sendable, Equatable {
    case none
    case standard
    case bow
}

/// 一段攻击经过 mod / 紫卡 / 灵化 / buff 处理后的最终参数。
public struct ResolvedAttack: Sendable, Equatable {
    public var name: String
    /// 单发（单弹丸）基础伤害，已含 mod 的元素与物理加成、已完成元素合并。
    public var damage: [DamageType: Double]
    /// `damage` 的固定顺序快照，模拟时按它遍历。
    public var orderedDamage: [DamageEntry]
    /// 单发总伤害，预先算好。
    public var totalDamage: Double
    public var critChance: Double        // 小数，可以 > 1
    public var critMultiplier: Double
    /// 仅在未暴击的命中上出现的额外伤害（例如 Laetum 的 Devouring Attrition）。
    /// `nonCriticalDamageBonus` 是 +伤害倍率，`nonCriticalDamageChance` 是触发概率。
    public var nonCriticalDamageBonus: Double
    public var nonCriticalDamageChance: Double
    /// 每次暴击升级一档的概率（Vigilante 套装）。
    public var doubleCritChance: Double
    /// 暴击命中时额外触发 Slash 状态的概率（Hunter Munitions）。
    public var slashOnCriticalChance: Double
    /// 直接伤害对目标每一种已存在状态增加的倍率；Galvanized Shot 一类效果使用。
    public var directDamagePerStatusType: Double
    /// 已写入 `damage` / `dotBaseDamage` 的基础伤害加法池倍率。
    /// Gun CO 的通常实现需要把每状态值加回这个池，而不是再乘一次。
    public var baseDamageMultiplier: Double
    /// 少数攻击段的数据明确标记 Gun CO 为乘法伤害；默认的枪械是加法池。
    public var conditionalDamageIsMultiplicative: Bool
    public var damageVulnerabilityMultiplier: Double
    public var statusDamageVulnerabilityMultiplier: Double
    /// Final outgoing multipliers from named external effects.  Eclipse applies
    /// to both paths; Madurai applies only to direct hits.  They remain
    /// separate from base damage and faction so they do not get folded into a
    /// wrong additive pool.
    public var directDamageMultiplier: Double
    /// Multiplier applied only to the weapon's resolved direct-damage vector.
    /// It is intentionally separate from `directDamageMultiplier`: Cyte-09's
    /// source data boosts that vector with Ability Strength but does not feed
    /// the same multiplier into an independent Xata Void hit.
    public var weaponVectorDamageMultiplier: Double
    public var statusDamageMultiplier: Double
    /// Website Xata's Whisper display value, normalized to a ratio.  The
    /// simulator creates its separate Void hit from this value; it must not be
    /// folded into `damage`, because it does not inherit ordinary elemental
    /// faction bonuses or Gun-CO's per-status multiplier.
    public var xataDamageRatio: Double
    /// Toxic Lash's resolved ratio.  The melee-only 2x source rule is applied
    /// here from the weapon category, not in a view or caller.
    public var toxicLashDamageRatio: Double
    /// The site applies slot Toxin damage to Toxic Lash ticks separately from
    /// the weapon's post-combination damage vector.
    public var toxicLashToxinElementBonus: Double
    /// Status-damage pool used only by Toxic Lash ticks.  It remains distinct
    /// from ordinary weapon Toxin procs because the source adds its
    /// Toxin-specific status modifier at a different point.
    public var toxicLashStatusMultiplier: Double
    /// 网站“潜行”选项。仅近战时把每个实际暴击档位替换为对应的潜行倍率；
    /// 它不能被折进固定基础伤害，因为暴击档位、冷冻与爆头会在时间线中改变。
    public var stealth: Bool
    public var statusChance: Double      // 每弹丸，小数，可以 > 1
    /// 供伤害型状态使用的 Modded Base Damage：不含元素/物理类型加成。
    /// Crit、爆头与两次派系结算在状态机中按命中分别乘入。
    public var dotBaseDamage: Double
    /// Heat / Electricity / Toxin 等状态各自吃的元素伤害加成。
    public var dotElementBonuses: [DamageType: Double]
    /// 仅作用于某一状态种类的伤害加成（例如 Emerald Shard 的 Toxin）。
    public var dotStatusBonuses: [DamageType: Double]
    public var multishot: Double
    /// 只在「弹匣最后一发」上额外增加的多重射击（灵化 `l_add_multishot`）。
    public var lastShotMultishot: Double
    public var fireRate: Double
    /// 已经吃过 `charge_time` 速度修正、且按游戏下限夹住后的完整蓄力时间。
    public var chargeTime: Double
    public var chargeTiming: ChargeTiming
    /// Default melee-combo data resolved from the weapon's `compTags`.  Nil
    /// means this attack uses the ordinary ranged / one-hit schedule.
    public var meleeSequence: MeleeAttackSequence?
    /// True only when this particular melee segment is evaluated as a heavy
    /// attack (the website switch or an `isHeavy` attack record).  It is kept
    /// with the resolved segment because the timeline, not the input view,
    /// owns combo consumption and per-contact multipliers.
    public var isHeavyMeleeAttack: Bool
    /// Normal melee contacts may still read a chosen combo multiplier for
    /// source-data actions such as Blood Rush and Weeping Wounds.  It is not
    /// a direct-damage multiplier unless `isHeavyMeleeAttack` is true.
    public var meleeComboMultiplier: Double
    /// Website heavy-attack start setting, in x-combo units (1...13).
    public var heavyStartingComboMultiplier: Double
    /// Initial combo points supplied by source-data Mods/custom stat.  Points
    /// rather than x-combo are retained because the website consumes points.
    public var initialComboPoints: Double
    /// Source-data heavy-attack efficiency, clamped by the rules to 0...0.9.
    public var heavyComboEfficiency: Double
    /// Relative chance additions per combo step.  These remain separate from
    /// the static chance so the simulator can apply the actual contact's
    /// current combo state rather than a SwiftUI-precomputed value.
    public var critChancePerCombo: Double
    public var statusChancePerCombo: Double
    /// Base chance used by the combo-relative actions above, before their
    /// per-contact combo step is added.
    public var baseCritChanceForCombo: Double
    public var baseStatusChanceForCombo: Double
    public var magazine: Double
    public var reload: Double
    public var burstCount: Int
    public var burstDelay: Double
    public var factionBonus: Double      // 小数，例如 0.3
    public var statusDamageBonus: Double // 小数
    public var statusDuration: Double    // 秒
    /// Additional Corrosive stack cap supplied by this resolved build's
    /// Archon Shard slots.
    public var corrosiveStackCapBonus: Double
    public var headshotMultiplier: Double
    /// 武器数据指定的额外强制状态；它们在常规状态抽样之外单独结算。
    public var forceProcs: [String]
    public var notes: [String]

}

/// 把「武器 + 装配 + 选项」折成每段攻击的参数。
public struct BuildResolver: Sendable {
    public let weapon: Weapon
    public let build: Build
    public let options: Options
    public let faction: FactionProfile
    public let library: ModLibrary

    public init(weapon: Weapon, build: Build, options: Options,
                faction: FactionProfile, library: ModLibrary = .shared) {
        self.weapon = weapon
        self.build = build
        self.options = options
        self.faction = faction
        self.library = library
    }

    /// 先按照界面槽位排列，再依次把普通 Mod 或紫卡交给同一个聚合器。紫卡
    /// 不是普通数据表条目，但它的元素词条同样必须出现在用户放置的那个位置。
    private struct OrderedBuildInput {
        var slot: Int
        var order: Int
        var modName: String?
        var riven: Riven?
        /// See `SlottedMod.actionScale`. This belongs to the concrete card in
        /// this slot, never to a similarly named card elsewhere in the build.
        var actionScale: Double?
        /// See `SlottedMod.conditionalStepScale`. This changes how many
        /// concrete condition inputs reach a source-defined cap; it does not
        /// lower the cap itself.
        var conditionalStepScale: Double?
    }

    private func orderedBuildInputs(notes: inout [String]) -> [OrderedBuildInput] {
        let source: [SlottedMod]
        if build.slottedMods.isEmpty {
            source = build.mods.enumerated().map { SlottedMod(slot: $0.offset, name: $0.element) }
        } else {
            source = build.slottedMods
        }

        let explicitlyNamedRivenSlot = source.first {
            BuildResolver.normalize($0.name) == BuildResolver.normalize("Riven")
        }?.slot
        let placedRivenSlot = build.rivenSlot ?? explicitlyNamedRivenSlot
        var inputs: [OrderedBuildInput] = []

        for (order, entry) in source.enumerated() {
            if BuildResolver.normalize(entry.name) == BuildResolver.normalize("Riven") {
                continue
            }
            if let placedRivenSlot, placedRivenSlot == entry.slot, build.riven != nil {
                notes.append("紫卡占用槽位 \(entry.slot)，已忽略同槽 Mod: \(entry.name)")
                continue
            }
            inputs.append(OrderedBuildInput(slot: entry.slot, order: order,
                                            modName: entry.name, riven: nil,
                                            actionScale: entry.actionScale,
                                            conditionalStepScale: entry.conditionalStepScale))
        }

        if let riven = build.riven {
            inputs.append(OrderedBuildInput(slot: placedRivenSlot ?? Int.max,
                                            order: source.count,
                                            modName: nil, riven: riven,
                                            actionScale: nil,
                                            conditionalStepScale: nil))
        } else if let explicitlyNamedRivenSlot {
            notes.append("槽位 \(explicitlyNamedRivenSlot) 标为紫卡，但没有紫卡词条")
        }

        return inputs.sorted {
            $0.slot == $1.slot ? $0.order < $1.order : $0.slot < $1.slot
        }
    }

    /// mod 与武器的兼容判定。
    ///
    /// 站点的 `tags` 有两层含义：多数是武器类别（`primary-rifle`），
    /// 少数是具体武器名的大写形式（`RIPKAS`）。两边都归一化成小写去比较。
    public func modApplies(_ mod: ModDefinition, at slot: Int? = nil) -> Bool {
        if mod.type == "frame_mod" { return false }
        // Archon Shards are explicit loadout slots, not weapon-tagged Mods.
        // Accept them only in the five site-equivalent shard positions.
        if mod.type == "shard" {
            guard let slot else { return false }
            return (23...27).contains(slot)
        }
        return tagsApply(mod.tags)
    }

    /// 外部来源是用户明确列出的战甲/同伴/环境 Mod，因而允许 `frame_mod`；
    /// 它仍必须带有能匹配当前武器的 tag，不能让一个只作用于技能或近战的条目
    /// 无条件影响任意枪械。
    private func externalModApplies(_ mod: ModDefinition) -> Bool {
        tagsApply(mod.tags)
    }

    private func tagsApply(_ tags: [String]?) -> Bool {
        guard let tags, !tags.isEmpty else { return false }
        var weaponKeys = Set<String>()
        weaponKeys.insert(BuildResolver.normalize(weapon.name))
        for t in weapon.categories ?? [] { weaponKeys.insert(BuildResolver.normalize(t)) }
        for t in weapon.compTags ?? [] { weaponKeys.insert(BuildResolver.normalize(t)) }
        if let c = weapon.category { weaponKeys.insert(BuildResolver.normalize(c)) }
        if let t = weapon.type { weaponKeys.insert(BuildResolver.normalize(t)) }
        for tag in tags {
            if weaponKeys.contains(BuildResolver.normalize(tag)) { return true }
        }
        return false
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Website weapon `unique` records may contain a static action and a
    /// `WITH_COND` override. When the global condition switch is on, its
    /// values replace only keys that it explicitly supplies; all other source
    /// keys remain present. This resolves raw data once in the core rather than
    /// teaching an input view a weapon-name formula.
    private static func activeUniqueAction(_ raw: [String: JSONValue],
                                           allConditionsMet: Bool) -> [String: JSONValue] {
        var action = raw
        let conditional = action.removeValue(forKey: "WITH_COND")?.objectValue
        guard allConditionsMet, let conditional else { return action }
        for (key, value) in conditional { action[key] = value }
        return action
    }

    public func resolveAll() -> [ResolvedAttack] {
        weapon.attacks.map { resolve(attack: $0) }
    }

    public func resolve(attack: Attack) -> ResolvedAttack {
        var agg = ModAggregate()
        var notes: [String] = []

        // 1. 收集 mod。合法性必须在写入聚合器之前完成：此前这里先应用、再
        // “检查”互斥，导致结果和 notes 相互矛盾。
        var acceptedMods: [ModDefinition] = []
        var seenMods = Set<String>()
        for input in orderedBuildInputs(notes: &notes) {
            if let riven = input.riven {
                agg.apply(riven: riven, notes: &notes)
                continue
            }
            guard let suppliedName = input.modName else { continue }
            guard let mod = library.mod(named: suppliedName) else {
                notes.append("未知 mod: \(suppliedName)")
                continue
            }

            let key = BuildResolver.normalize(mod.name)
            guard seenMods.insert(key).inserted else {
                notes.append("重复 mod 被忽略: \(mod.name)")
                continue
            }
            guard modApplies(mod, at: input.slot) else {
                notes.append("mod 与该武器不兼容: \(mod.name)")
                continue
            }

            let conflicts = Set((mod.uncomp ?? []).map(BuildResolver.normalize))
            let conflictsWithAccepted = acceptedMods.contains { accepted in
                let acceptedKey = BuildResolver.normalize(accepted.name)
                if conflicts.contains(acceptedKey) { return true }
                return Set((accepted.uncomp ?? []).map(BuildResolver.normalize)).contains(key)
            }
            guard !conflictsWithAccepted else {
                notes.append("互斥 mod 被忽略: \(mod.name)")
                continue
            }

            acceptedMods.append(mod)
            agg.apply(mod: mod,
                      conditionalRule: library.conditionalRule(named: mod.name),
                      weapon: weapon, attack: attack, options: options,
                      actionScale: input.actionScale,
                      conditionalStepScale: input.conditionalStepScale,
                      notes: &notes)
        }

        // 战甲/同伴/任务环境不是武器配卡的第十一个槽位。调用者必须显式把
        // 来源填进 options.environment；名称只在 `mod` 字段明确给出时才查询数据表。
        for source in options.environment.allSources where source.active {
            agg.apply(externalBuff: source.buff)
            guard let requestedMod = source.mod else { continue }
            guard let mod = library.mod(named: requestedMod) else {
                notes.append("外部来源找不到 Mod: \(requestedMod)（\(source.name)）")
                continue
            }
            guard externalModApplies(mod) else {
                notes.append("外部 Mod 与该武器不兼容: \(mod.name)")
                continue
            }
            agg.apply(externalMod: mod, source: source, weapon: weapon, attack: attack,
                      options: options, notes: &notes)
        }

        // 2. 灵化进化节点
        if !build.incarnonPerks.isEmpty {
            applyIncarnon(&agg, attack: attack, notes: &notes)
        }

        // 少数武器把状态伤害修正直接放在 weapon / attack 的 `unique` 上。
        // 这些是公式数据，而不是 README 的说明文字；在折算攻击段时一并读取。
        if let unique = weapon.unique {
            agg.apply(json: Self.activeUniqueAction(unique,
                                                    allConditionsMet: options.allModConditionsMet),
                      from: .mod, notes: &notes)
        }
        if let unique = attack.unique {
            agg.apply(json: Self.activeUniqueAction(unique,
                                                    allConditionsMet: options.allModConditionsMet),
                      from: .mod, notes: &notes)
        }

        // `customStats` is a typed input contract shared by the native UI and
        // parity fixtures.  Keep its mechanics here, next to ordinary Mod and
        // Incarnon aggregation, rather than teaching an input view how damage
        // formulae work.
        if !options.unrecognizedCustomStatKeys.isEmpty {
            notes.append("未知自定义属性: " + options.unrecognizedCustomStatKeys.joined(separator: ","))
        }

        // 4. 折成最终数值
        //
        // 灵化的 `flat_change_dmg`（wiki 原文 "Increase Base Damage by +51"）是加在
        // **基础伤害**上的固定值：先按该段原有伤害构成等比例摊到各类型，再一起吃
        // +伤害% mod 与元素 mod。来源：<https://wiki.warframe.com/w/Torid>（EVO2 Final Fusillade）
        // 赤毒 / 信条继承元素首先是这一把实例的基础伤害组成：它和武器原始
        // 伤害一起吃 Serration，随后才与槽位元素按顺序合并。不能把它伪装成
        // 外部附伤或一个普通元素 Mod。
        let isMelee = weapon.category?.caseInsensitiveCompare("Melee") == .orderedSame
            || (weapon.categories ?? []).contains {
                $0.caseInsensitiveCompare("melee") == .orderedSame
            }
        let isHeavyMeleeAttack = isMelee && (options.heavyAttack || attack.isHeavy)

        // This is the equipped/current Warframe's resolved Ability Strength,
        // not a UI-side multiplier.  A separately cast external ability keeps
        // its own source-specific strength in `ExternalEffectSource`. The
        // source discriminator is decoded with the weapon and resolved here
        // so each effect retains its documented pool:
        // simple/excalibur are final direct-and-status factors; Mesa is base
        // damage; Cyte-09 changes only the weapon vector.
        let abilityStrength = max(0, options.abilityStrength)
        let strengthType = Self.normalize(weapon.strengthType ?? "")
        let simpleStrengthMultiplier = (strengthType == "simple" || strengthType == "excalibur")
            ? abilityStrength : 1
        let cyteWeaponVectorMultiplier = strengthType == "cyte"
            ? 1.25 * abilityStrength : 1
        let mesaBaseDamageBonus = strengthType == "mesa" ? 1.5 * abilityStrength : 0
        let additionalWeaponMultiplier = max(0, weapon.additionalBuff ?? 1)

        let unmodifiedBaseTotal = attack.damage.totalDamage
        var baseDamage = attack.damage
        for (rawType, ratio) in build.progenitorElements {
            guard let type = DamageType(dataKey: rawType), type.isPrimaryElement else { continue }
            baseDamage[type, default: 0] += unmodifiedBaseTotal * max(0, ratio)
        }
        let rawBaseTotal = baseDamage.totalDamage
        let flatDamage = agg.flatDamage
            + agg.flatDamageByAbilityStrength * abilityStrength
            + options.customStat(.flatChangeDamage)
        if flatDamage != 0 && rawBaseTotal > 0 {
            for (t, v) in baseDamage.ordered {
                baseDamage[t] = v + flatDamage * (v / rawBaseTotal)
            }
        }

        let damageBonus = agg.damageBonus + mesaBaseDamageBonus + options.warframe.damageBonus
            + options.customStat(.base)
            + (isHeavyMeleeAttack ? agg.heavyDamageBonus : 0)
        var damage: [DamageType: Double] = [:]
        for (t, v) in baseDamage.ordered { damage[t] = v * (1 + damageBonus) }

        // Damage-over-time does not use the post-element / post-physical damage
        // vector.  It is seeded from Modded Base Damage instead.
        let dotBaseDamage = (rawBaseTotal + flatDamage) * (1 + damageBonus)
        // The site's `heatAdd` custom input is an independent Heat instance
        // calculated from the unmodded base damage.  It is not a slot element:
        // it is appended after HCET merging, but it also supplies the matching
        // Heat-status elemental bonus.
        let customHeatAdd = max(0, options.customStat(.heatAdd))
        // `heatInherit` is the website's Heat-DOT-only override.  When it is
        // positive it replaces the ordinary Heat element-bonus pool for Heat
        // ticks; it does not alter the direct-hit vector or other DOT types.
        let customHeatInherit = max(0, options.customStat(.heatInherit))
        var dotElementBonuses: [DamageType: Double] = [:]
        // The ordinary damaging-status element bonuses are primary elements;
        // Gas additionally has explicit Gas-damage sources (for example
        // Leaded Gas / Valence Formation), which must not be discarded merely
        // because Gas itself is a combined element.
        for (type, bonus) in agg.elements
            where type == .heat || type == .electricity || type == .toxin || type == .gas {
            dotElementBonuses[type, default: 0] += bonus
        }
        for (type, bonus) in agg.externalDotElementBonuses
            where type == .heat || type == .electricity || type == .toxin || type == .gas {
            dotElementBonuses[type, default: 0] += bonus
        }
        if customHeatAdd > 0 {
            dotElementBonuses[.heat, default: 0] += customHeatAdd
        }
        if customHeatInherit > 0 {
            dotElementBonuses[.heat] = customHeatInherit
        }

        // 物理 mod 加的是「该类型在基础伤害里的占比 × 数值」，所以按基础值乘
        for (t, v) in agg.physical where t.isPhysical {
            let base = baseDamage[t] ?? 0
            damage[t, default: 0] += base * (1 + damageBonus) * v
        }

        let moddedTotal = damage.totalDamage
        let modElements: [(DamageType, Double)] = agg.elements.map { ($0.0, moddedTotal * $0.1) }
        damage = BuildResolver.mergeElements(base: damage, mods: modElements)
        // 外部赋能（例如 Venom Dose、Shock Trooper）在武器自己的元素槽位已经
        // 合并后附加，不能再被当作一个随机位置的元素 Mod 合成掉。
        for (type, ratio) in agg.externalElements {
            damage[type, default: 0] += rawBaseTotal * ratio
        }
        if customHeatAdd > 0 {
            damage[.heat, default: 0] += rawBaseTotal * customHeatAdd
        }
        // Nourish is an external Viral instance, not a weapon-slot elemental
        // Mod. It is therefore appended after HCET slot merging. Unlike the
        // ordinary external imbues above, the website scales Nourish from
        // Modded Base Damage (the same seed used by status damage), not the
        // unmodded weapon base.
        let nourishBonus = options.scenarioEffects.value(for: .nourish)
        if nourishBonus != 0 {
            damage[.viral, default: 0] += dotBaseDamage * nourishBonus
        }
        // Direct-hit components are quantized in game in units of Modded Base / 32.
        // Do this after physical/elemental construction but before falloff, crit,
        // faction, and target-side modifiers.  Damage-over-time deliberately keeps
        // the full-precision `dotBaseDamage` calculated above.
        damage = BuildResolver.quantizeDirectDamage(damage, moddedBaseDamage: dotBaseDamage)

        // 伤害衰减：只有给了距离才算；没给距离按「全部命中在 start 内」处理。
        if let falloff = attack.falloff, let distance = options.distance {
            let span = max(falloff.end - falloff.start, 1e-9)
            let ratio = min(max((distance - falloff.start) / span, 0), 1)
            let factor = max(0, 1 - falloff.reduction * ratio)
            for (t, v) in damage { damage[t] = v * factor }
        } else if attack.falloff != nil {
            notes.append("该段有伤害衰减，未给 distance，按满伤害计算")
        }

        // 暴击：基础暴伤先量化，mod 的相对加成在量化之后乘
        let baseCritDamage = Rules.quantizeBaseCritDamage(attack.critMultiplier)
        // 暴击率不可能为负：负值紫卡的下降幅度可以吃掉整份基础暴击率，
        // 而游戏里的下界就是 0%。不在这里夹住，`ResolvedAttack.critChance`
        // 会对外暴露负数（Laetum 配负暴击率紫卡时实测 -0.0618），下游靠
        // `expectedCritMultiplier` 的 max(0,…) 兜底才没让伤害出错。
        let weakPointCritChance = options.weakPoint
            ? agg.critChanceWeakPoint + options.customStat(.weakPointCritChance)
            : 0
        let critChance = max(0, ((attack.critChance / 100)
            * (1 + agg.critChanceRelative + options.warframe.critChanceBonus
               + options.customStat(.critChance) + weakPointCritChance)
            + agg.critChanceAbsolute + options.customStat(.flatCritChance)
            + options.scenarioEffects.value(for: .flatCriticalChance))
            * (1 + options.customStat(.multiplicativeCritChance)))
        let critMultiplier = (baseCritDamage
            * (1 + agg.critDamageRelative
               + (isHeavyMeleeAttack ? agg.heavyCritDamageRelative : 0)
               + options.customStat(.critMultiplier))
            + agg.critDamageAbsolute + options.warframe.critDamageBonus
            + options.customStat(.flatCritMultiplier))
            * (1 + options.customStat(.finalCritMultiplier))

        // The site applies the absolute status term after ordinary relative
        // status scaling, then applies the status-vulnerability multiplier to
        // the completed chance. `absolute_status_chance` uses raw percentage
        // points in its UI/internal contract, unlike the percentage-input keys.
        let statusChance = ((attack.statusChance / 100 + agg.statusChanceAbsolute)
            * (1 + agg.statusChanceRelative
               + (isHeavyMeleeAttack ? agg.heavyStatusChanceRelative : 0)
               + options.customStat(.statusChance))
            + options.customStat(.absoluteStatusChance) / 100)
            * (1 + options.customStat(.statusChanceMultiplier))

        let baseMultishot = attack.multishot ?? weapon.multishot ?? 1
        let multishot = agg.locksMultishot
            ? baseMultishot
            : baseMultishot * (1 + agg.multishot + options.warframe.multishotBonus
                               + options.customStat(.multishot)) + agg.multishotAbsolute

        // Cannonade 类动作把射速固定回基础值；与 multishot 的同类锁定一样，
        // 不能只记录标志却继续套用所有加成。
        let fireRate = agg.locksFireRate
            ? attack.speed
            : attack.speed * (1 + agg.fireRate + options.warframe.fireRateBonus
                              + options.customStat(.speed))

        // 灵化形态用的是 incMagazineSize，而且**不吃任何 mod**（包括灵化的 +9 弹匣）。
        // 来源：<https://wiki.warframe.com/w/Torid>（"Incarnon Form's magazine is not affected by mods"）
        let magazine: Double
        if attack.isIncarnonForm {
            magazine = max(1, weapon.incarnonMagazineSize ?? weapon.magazineSize ?? 1)
        } else {
            // `add_magazineSize` 加的是**基础**弹匣容量，所以先加固定值再吃 +弹匣% mod。
            magazine = max(1, ((weapon.magazineSize ?? 1) + agg.flatMagazine)
                * (1 + agg.magazine + options.customStat(.magazineSize)))
        }
        let reload = max(0, (weapon.reloadTime ?? 0)
            / (1 + agg.reloadSpeed + options.customStat(.reloadTime)))

        let factionBonus = (agg.faction[faction.canonical] ?? 0) + agg.anyFactionBonus
            + options.warframe.factionBonus + options.scenarioEffects.value(for: .roar)
        let headshot: Double
        if options.headshot && !attack.noHeadshotMultiplier {
            // Ordinary headshot modifiers are relative to the body-part multiplier:
            // 3x with +30% becomes 3 × 1.3, not 3.3x.  Weak-point damage is a
            // separate additive term on the target's body-part multiplier; Acuity's
            // data value is already the 1.5x headshot-adjusted bonus (5.25 for its
            // listed +350%), so a normal 3x head weak point becomes 3 + 5.25 = 8.25.
            headshot = (options.headshotMultiplier + options.customStat(.weakPointDamage))
                * (1 + agg.headshotBonus + options.customStat(.headshotDamage))
                + (options.weakPoint ? agg.weakPointHeadshotBonus : 0)
        } else {
            headshot = 1
        }

        if attack.burstCount ?? 1 > 1 {
            notes.append("burst 按 burst_delay 展开，未计入切换延迟")
        }
        if !agg.unsupported.isEmpty {
            let sorted = agg.unsupported.sorted()
            notes.append("未实现的 mod 动作: " + sorted.joined(separator: ","))
        }
        if !agg.unsupportedIncarnon.isEmpty {
            let sorted = agg.unsupportedIncarnon.sorted()
            notes.append("未实现的灵化动作: " + sorted.joined(separator: ","))
        }

        // A stance Mod's `action.stances` is data for the selected normal combo,
        // not a numeric stat to merge into `ModAggregate`.  Resolve it only
        // after slot compatibility has accepted the Mod, so an arbitrary Mod
        // cannot inject a combo through the input layer.
        let selectedStance = acceptedMods.first {
            $0.type?.caseInsensitiveCompare("stance") == .orderedSame
        }
        let stanceCombos = selectedStance.map {
            MeleeStanceLibrary.combos(in: $0, orderedNames: library.stanceComboNames(for: $0.name))
        } ?? []
        if let requestedCombo = build.stanceCombo,
           !stanceCombos.contains(where: {
               $0.name.caseInsensitiveCompare(requestedCombo) == .orderedSame
           }) {
            notes.append("架势连段无效或未装备对应架势: \(requestedCombo)")
        }
        // The source applies wind-up actions as a speed term on the weapon's
        // heavy wind-up before it builds the contact timeline.  Keep that
        // transformed value inside the core; SwiftUI never receives a timing
        // formula or precomputed attack count.
        var meleeTimingWeapon = weapon
        let windUpDivisor = max(1e-9, 1 + agg.windUpSpeed)
        meleeTimingWeapon.windUp = max(0, (weapon.windUp ?? 0) / windUpDivisor)
        let meleeSequence = MeleeStanceLibrary.sequence(
            for: meleeTimingWeapon,
            attack: attack,
            stanceMod: selectedStance,
            comboName: build.stanceCombo,
            orderedNames: selectedStance.map { library.stanceComboNames(for: $0.name) } ?? [],
            heavy: isHeavyMeleeAttack
        )

        let ordered = damage.ordered.map { DamageEntry(type: $0.0, value: $0.1) }
        let total = ordered.reduce(0) { $0 + $1.value }
        // Condition Overload / Gun CO 的层数、数值和适用攻击段全都来自
        // conditional-effects.json。这里不再知道任何具体 Mod 的名称。
        let directDamagePerStatusType = agg.directDamagePerStatusType(
            for: attack, options: options)
        let chargeTime: Double
        let chargeTiming: ChargeTiming
        if let baseChargeTime = attack.chargeTime {
            // Charge Time 是一个“时间”属性：+charge speed 通过分母缩短它；
            // 最低只能到基础时间的 1/10。数据中的 charge_time 已是适用于
            // 这一攻击类别的汇总速度加成（primary-bow 的 FOR_WEAPON 覆盖
            // 也已在聚合前完成），故不能再把 fireRate 重复乘进去。
            chargeTime = max(0, baseChargeTime) / max(0.1, 1 + agg.chargeTimeBonus)
            let isBow = (weapon.categories ?? []).contains {
                BuildResolver.normalize($0) == "primarybow"
            }
            chargeTiming = isBow ? .bow : .standard
        } else {
            chargeTime = 0
            chargeTiming = .none
        }

        let eclipseMultiplier = max(0, 1 + options.scenarioEffects.value(for: .eclipse))
        let powerWeapon = (weapon.compTags ?? []).contains {
            $0.caseInsensitiveCompare("POWER_WEAPON") == .orderedSame
        }
        // The website's Madurai control is a fixed direct-hit 1.3× modifier
        // and excludes POWER_WEAPON-tagged attacks.  It does not appear in
        // the website's damage-over-time routine.
        let maduraiMultiplier = options.scenarioEffects.value(for: .madurai) > 0 && !powerWeapon
            ? 1.3 : 1
        // These two controls are site-level input contracts, but their effects
        // belong here with the resolved attack.  `abilityCombo` is a special
        // Exalted Weapon multiplier; the custom attribute and the checkbox use
        // the larger value, exactly as the website source does.  `sniperCombo`
        // is not inferred from the weapon category: it applies only to an
        // attack explicitly carrying that source-data flag.  With the checkbox
        // off, the website retains the attack's built-in 1.5x multiplier.
        let isExaltedWeapon = weapon.type?.caseInsensitiveCompare("Exalted Weapon") == .orderedSame
        let requestedAbilityCombo = max(1, options.abilityComboMultiplier ?? 1,
                                        options.customStat(.abilityCombo))
        let abilityComboMultiplier = isExaltedWeapon && requestedAbilityCombo > 1
            ? requestedAbilityCombo : 1
        let sniperComboMultiplier = attack.sniperCombo
            ? max(1, options.sniperComboMultiplier ?? 1.5) : 1
        let siteComboMultiplier = abilityComboMultiplier * sniperComboMultiplier
        let resolvedStatusDamageBonus = agg.statusDamage
            + (isHeavyMeleeAttack ? agg.heavyStatusDamage : 0)
            + options.warframe.statusDamageBonus
            + options.customStat(.statusDamage)
        let statusDamageVulnerabilityMultiplier = max(
            0, 1 + options.customStat(.vulnerableStatusDamage)
        )
        // `toxicLashDmg` in the website evaluates the general status pool,
        // then adds its Toxin-only status term rather than multiplying it.
        // The currently supported terms are kept explicit; unimplemented
        // conditional source actions remain reported by the aggregate instead
        // of silently being assumed active here.
        let toxicLashStatusMultiplier = max(
            0,
            (1 + resolvedStatusDamageBonus) * statusDamageVulnerabilityMultiplier
                + (agg.statusDamageByType[.toxin] ?? 0)
        )
        return ResolvedAttack(
            name: attack.name,
            damage: damage,
            orderedDamage: ordered,
            totalDamage: total,
            critChance: critChance,
            critMultiplier: critMultiplier,
            nonCriticalDamageBonus: agg.nonCriticalDamageBonus,
            nonCriticalDamageChance: agg.nonCriticalDamageChance,
            doubleCritChance: agg.doubleCritChance,
            slashOnCriticalChance: agg.slashOnCriticalChance,
            directDamagePerStatusType: directDamagePerStatusType,
            baseDamageMultiplier: 1 + damageBonus,
            conditionalDamageIsMultiplicative: attack.conditionalDamageIsMultiplicative
                || options.forceMultiplicativePerStatusDamage,
            // The site's `dmgVulnerability` is a target-side multiplier. It
            // applies to direct hits and status instances, not to the base
            // damage or faction pools.
            damageVulnerabilityMultiplier: max(0, 1 + options.customStat(.damageVulnerability)),
            // The site's `vuln_status_damage` is independent from additive
            // Elementalist-style status damage.
            statusDamageVulnerabilityMultiplier: statusDamageVulnerabilityMultiplier,
            directDamageMultiplier: eclipseMultiplier * maduraiMultiplier * siteComboMultiplier
                * simpleStrengthMultiplier * additionalWeaponMultiplier,
            weaponVectorDamageMultiplier: cyteWeaponVectorMultiplier,
            statusDamageMultiplier: eclipseMultiplier * siteComboMultiplier
                * simpleStrengthMultiplier * additionalWeaponMultiplier,
            xataDamageRatio: max(0, options.scenarioEffects.value(for: .xata)),
            toxicLashDamageRatio: max(0, options.scenarioEffects.value(for: .toxicLash))
                * (isMelee ? 2 : 1),
            toxicLashToxinElementBonus: agg.elements.reduce(0) { partial, entry in
                entry.0 == .toxin ? partial + entry.1 : partial
            },
            toxicLashStatusMultiplier: toxicLashStatusMultiplier,
            stealth: options.stealth && isMelee,
            statusChance: statusChance,
            dotBaseDamage: dotBaseDamage,
            dotElementBonuses: dotElementBonuses,
            dotStatusBonuses: agg.statusDamageByType,
            multishot: multishot,
            lastShotMultishot: agg.lastShotMultishot,
            fireRate: fireRate,
            chargeTime: chargeTime,
            chargeTiming: chargeTiming,
            meleeSequence: meleeSequence,
            isHeavyMeleeAttack: isHeavyMeleeAttack,
            meleeComboMultiplier: max(1, options.meleeComboMultiplier ?? 1),
            heavyStartingComboMultiplier: min(max(options.heavyAttackStartingCombo, 1), 13),
            initialComboPoints: max(0, agg.initialComboPoints + options.customStat(.initialCombo)),
            heavyComboEfficiency: min(max(agg.meleeComboEfficiency, 0), 0.9),
            critChancePerCombo: agg.critChancePerCombo,
            statusChancePerCombo: agg.statusChancePerCombo,
            baseCritChanceForCombo: max(0, attack.critChance / 100),
            baseStatusChanceForCombo: max(0, attack.statusChance / 100),
            magazine: magazine,
            reload: reload,
            burstCount: max(1, attack.burstCount ?? 1),
            burstDelay: attack.burstDelay ?? 0,
            factionBonus: factionBonus,
            statusDamageBonus: resolvedStatusDamageBonus,
            statusDuration: Rules.statusBaseDuration * (1 + agg.statusDuration),
            corrosiveStackCapBonus: agg.corrosiveStackCapBonus,
            headshotMultiplier: headshot,
            forceProcs: attack.forceProcs ?? [],
            notes: notes
        )
    }

    /// 元素两两合并。
    ///
    /// 优先级：mod 槽位顺序（左上→右下），然后武器固有元素。
    /// 固有元素排最后，是 wiki 明确写的；Kuva / Tenet 双固有元素按 HCET 排。
    /// 来源：<https://wiki.warframe.com/w/Damage>
    public static func mergeElements(base: [DamageType: Double],
                                     mods: [(DamageType, Double)]) -> [DamageType: Double] {
        var out: [DamageType: Double] = [:]
        var order: [DamageType] = []
        var pool: [DamageType: Double] = [:]

        func push(_ t: DamageType, _ v: Double) {
            if pool[t] == nil { order.append(t) }
            pool[t, default: 0] += v
        }

        for (t, v) in mods { push(t, v) }
        for t in DamageType.primaryOrder {
            if let v = base[t] { push(t, v) }
        }
        for (t, v) in base.ordered where !t.isPrimaryElement { out[t, default: 0] += v }

        var i = 0
        while i + 1 < order.count {
            let a = order[i], b = order[i + 1]
            if let combined = DamageType.combined(a, b) {
                out[combined, default: 0] += (pool[a] ?? 0) + (pool[b] ?? 0)
            } else {
                out[a, default: 0] += pool[a] ?? 0
                out[b, default: 0] += pool[b] ?? 0
            }
            i += 2
        }
        if i < order.count { out[order[i], default: 0] += pool[order[i]] ?? 0 }
        return out.filter { $0.value != 0 }
    }

    /// Mission-side direct damage is represented on a 1/32 grid of Modded Base
    /// Damage.  This must not be reused for DOT seeds: those use the unquantized
    /// Modded Base Damage by design.
    static func quantizeDirectDamage(_ damage: [DamageType: Double],
                                     moddedBaseDamage: Double) -> [DamageType: Double] {
        let scale = Float(max(0, moddedBaseDamage)) / 32
        guard scale > 0 else { return [:] }
        var result: [DamageType: Double] = [:]
        for (type, value) in damage {
            let signed = Float(value)
            let magnitude = abs(signed)
            let steps = floorf(magnitude / scale + 0.5)
            let quantized = steps * scale
            if quantized != 0 {
                result[type] = Double(signed < 0 ? -quantized : quantized)
            }
        }
        return result
    }

    private func applyIncarnon(_ agg: inout ModAggregate, attack: Attack, notes: inout [String]) {
        guard let tiers = weapon.incarnon else {
            notes.append("武器没有灵化数据")
            return
        }
        for pick in build.incarnonPerks {
            let parts = pick.split(separator: ":")
            guard parts.count == 2, let tier = Int(parts[0]), let index = Int(parts[1]) else {
                notes.append("灵化选择格式错误: \(pick)")
                continue
            }
            guard let node = tiers.first(where: { $0.tier == tier }) else {
                notes.append("没有这一级灵化: \(pick)")
                continue
            }
            guard index >= 0 && index < node.options.count else {
                notes.append("灵化选项越界: \(pick)")
                continue
            }
            let option = node.options[index]
            guard BuildResolver.incarnonApplies(option: option, attack: attack) else { continue }
            var action = option.action ?? [:]
            let conditional = action.removeValue(forKey: "WITH_COND")?.objectValue
            agg.apply(json: action, from: .incarnon, notes: &notes)
            if let conditional, !conditional.isEmpty {
                // 条件是否已经达成由输入的当前层数决定，而不是用本次命中去猜。
                let label = option.name.split(separator: ":").first.map(String.init) ?? option.name
                // Incarnon 的条件效果与 Mod 的条件效果走完全相同的数据表。
                // 例如 Lethal Rearmament 的 3 层 reload bonus 不应在这里另写一条
                // 武器专用公式，也不能因为它来自 Incarnon 就被标成未实现。
                agg.apply(conditional: conditional, staticAction: action, modName: label,
                          rule: library.conditionalRule(named: label), attack: attack,
                          options: options, notes: &notes)
            }
        }
    }

    /// 灵化选项的 `type` 与攻击段同名空间（`Normal Attack` / `Incarnon Form` / `Incarnon Mode`）。
    ///
    /// Torid 这类武器没有名字叫 `Normal Attack` 的攻击段（叫 `Grenade Impact` / `Poison Cloud`），
    /// 所以 `Normal Attack` 一律按「非灵化形态」理解，而不是当字面武器段名。
    static func incarnonApplies(option: IncarnonTier.IncarnonOption, attack: Attack) -> Bool {
        let types = option.type.filter { !$0.isEmpty }
        guard !types.isEmpty else { return true }
        let attackKey = normalize(attack.name)
        for raw in types {
            let key = normalize(raw)
            if key == attackKey { return true }
            if key == normalize("Normal Attack") && !attack.isIncarnonForm { return true }
            if (key == normalize("Incarnon Form") || key == normalize("Incarnon Mode")) && attack.isIncarnonForm {
                return true
            }
        }
        return false
    }
}

/// mod 效果的累加器。
struct ModAggregate {
    /// 动作来自普通 mod 还是灵化进化。
    /// 同一个键在两边含义可能不同（见 `mutatingApply` 里的 `base`）。
    enum Source { case mod, incarnon }

    var damageBonus: Double = 0
    var elements: [(DamageType, Double)] = []
    /// 外部赋能的元素附伤：按 Modded Base Damage 计，且不参与武器槽位的
    /// HCET 合并顺序。
    var externalElements: [(DamageType, Double)] = []
    /// 外部效果明确提供的状态元素伤害加成（例如 Shock Trooper 的
    /// electricity_scaledByStrength），与直接附伤分开保存。
    var externalDotElementBonuses: [(DamageType, Double)] = []
    var physical: [DamageType: Double] = [:]
    var critChanceRelative: Double = 0
    var critChanceAbsolute: Double = 0
    var critChanceWeakPoint: Double = 0
    /// Blood Rush / Gladiator-style relative chance granted for each combo
    /// step. It is consumed per simulated melee contact, not when the UI
    /// changes a numeric field.
    var critChancePerCombo: Double = 0
    var critDamageRelative: Double = 0
    var critDamageAbsolute: Double = 0
    /// Dreamer's Wrath and similar: only a heavy attack receives this term.
    var heavyCritDamageRelative: Double = 0
    var nonCriticalDamageBonus: Double = 0
    var nonCriticalDamageChance: Double = 0
    var doubleCritChance: Double = 0
    var slashOnCriticalChance: Double = 0
    /// 每状态直接伤害效果。原始 Mod 数据只给数值；是否常驻、要多少击杀层
    /// 以及是否排除 AoE 均由 `conditional-effects.json` 声明。
    private struct PerStatusDamageEffect: Sendable {
        var mod: String
        var valueAtFullEffect: Double
        var maxStacks: Double
        var activation: ConditionalEffectRule.PerStatusDamage.Activation
        var excludedShotTypes: Set<String>
    }
    private var perStatusDamageEffects: [PerStatusDamageEffect] = []
    var statusChanceRelative: Double = 0
    var statusChanceAbsolute: Double = 0
    /// Weeping Wounds-style relative status per combo step, plus the
    /// heavy-only status term from Empowered Blades.
    var statusChancePerCombo: Double = 0
    var heavyStatusChanceRelative: Double = 0
    var multishot: Double = 0
    var multishotAbsolute: Double = 0
    var fireRate: Double = 0
    var reloadSpeed: Double = 0
    var magazine: Double = 0
    var flatMagazine: Double = 0
    /// 灵化 `flat_change_dmg`：直接加在基础伤害上的固定值。
    var flatDamage: Double = 0
    /// Source actions explicitly marked `flat_change_dmg_by_strength`. The
    /// global multiplier is applied only after the owning weapon's raw action
    /// has been selected; it is not a frontend-precomputed damage value.
    var flatDamageByAbilityStrength: Double = 0
    var lastShotMultishot: Double = 0
    var statusDamage: Double = 0
    var heavyStatusDamage: Double = 0
    var statusDamageByType: [DamageType: Double] = [:]
    var statusDuration: Double = 0
    /// Sum from selected Emerald Shards.  This deliberately remains separate
    /// from the global Options value so a concrete shard card can be audited
    /// in the build that supplied it.
    var corrosiveStackCapBonus: Double = 0
    var faction: [String: Double] = [:]
    var anyFactionBonus: Double = 0
    var headshotBonus: Double = 0
    /// Additive weak-point term on a headshot body-part multiplier.  This differs
    /// from ordinary `mult_for_head`, which is relative to that multiplier.
    var weakPointHeadshotBonus: Double = 0
    /// `charge_time` action 的总“蓄力速度”加成（不是已换算的秒数）。
    var chargeTimeBonus: Double = 0
    /// Heavy-attack-only source-data actions. `initialCombo` is expressed in
    /// points; `windUp` is a speed bonus used as a denominator.
    var heavyDamageBonus: Double = 0
    var initialComboPoints: Double = 0
    var meleeComboEfficiency: Double = 0
    var windUpSpeed: Double = 0
    var locksMultishot = false
    var locksFireRate = false
    var unsupported: Set<String> = []
    var unsupportedIncarnon: Set<String> = []

    mutating func apply(mod: ModDefinition, conditionalRule: ConditionalEffectRule?,
                        weapon: Weapon, attack: Attack, options: Options,
                        actionScale: Double? = nil,
                        conditionalStepScale: Double? = nil,
                        notes: inout [String]) {
        var action = mod.action ?? [:]
        // FOR_WEAPON 覆盖普通 action 的同名键；例如 Critical Delay 的 bow
        // 版本用 -40% charge time 取代一般的 -20%。
        if let perWeapon = action.removeValue(forKey: "FOR_WEAPON")?.objectValue {
            for (tag, raw) in perWeapon where Self.weapon(weapon, matches: tag) {
                for (key, value) in raw.objectValue ?? [:] { action[key] = value }
            }
        }
        if let actionScale {
            guard actionScale.isFinite, actionScale >= 0 else {
                notes.append("已忽略无效的 Mod 等级倍率: \(mod.name)")
                return
            }
            if abs(actionScale - 1) > .ulpOfOne {
                // The inventory adapter only emits a scale after proving that
                // the source card's whole action is proportional at this rank.
                // Keeping the multiplication here makes every subsequent
                // branch (including a data-table conditional) consume the same
                // concrete equipped-card value instead of a UI-side estimate.
                action = Self.scaledAction(action, by: actionScale)
            }
        }
        // Most upstream records put triggered values under WITH_COND. A small
        // documented set keeps the same full value in its ordinary action;
        // the companion rule resource moves only those declared keys into
        // this shared condition path, without altering the website mirror.
        var conditionalAction = action.removeValue(forKey: "WITH_COND")?.objectValue ?? [:]
        for key in conditionalRule?.conditionalActionKeys ?? [] {
            if let value = action.removeValue(forKey: key) {
                conditionalAction[key] = value
            }
        }
        var conditional: [String: JSONValue]? = conditionalAction.isEmpty ? nil : conditionalAction
        // A few source records put a full-rank passive and an ordinary stacked
        // trigger in the same WITH_COND object. The resource rule, rather
        // than a Mod-name branch here or in SwiftUI, tells the resolver which
        // keys are permanent. Promote those values before applying either the
        // normal action or the remaining conditional branch.
        if var conditionalAction = conditional,
           let alwaysActiveKeys = conditionalRule?.alwaysActiveKeys {
            for key in alwaysActiveKeys {
                if let value = conditionalAction.removeValue(forKey: key) {
                    action[key] = value
                }
            }
            conditional = conditionalAction
        }
        if let value = action.removeValue(forKey: "base_per_status")?.doubleValue {
            registerPerStatusDamage(valueAtFullEffect: value, modName: mod.name,
                                    rule: conditionalRule, notes: &notes)
        }
        mutatingApply(action: action, modName: mod.name, source: .mod, notes: &notes)

        if let conditional, !conditional.isEmpty {
            apply(conditional: conditional, staticAction: action, modName: mod.name,
                  rule: conditionalRule, attack: attack, options: options,
                  conditionalStepScale: conditionalStepScale, notes: &notes)
        }
        if mod.action?["set"] != nil { /* 套装加成未实现 */ }
    }

    /// Scale numeric leaves while preserving source-data structure. This is
    /// intentionally private: callers may supply an `actionScale` only when
    /// their import layer has verified the complete card action is linear.
    ///
    /// Vigilante's `double_crit` is deliberately an exception: it is a fixed
    /// 5% set contribution for each equipped Vigilante card, not a fusion-rank
    /// coefficient of that individual card. The snapshot adapter validates
    /// and scales the printed card stat, while this value must remain intact.
    private static func scaledAction(_ action: [String: JSONValue], by scale: Double) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: action.map { key, value in
            let rankIndependent = key == "double_crit" || key == "stances" || key == "set"
            return (key, rankIndependent ? value : scaledJSONValue(value, by: scale))
        })
    }

    private static func scaledJSONValue(_ value: JSONValue, by scale: Double) -> JSONValue {
        switch value {
        case .number(let number):
            return .number(number * scale)
        case .array(let values):
            return .array(values.map { scaledJSONValue($0, by: scale) })
        case .object(let values):
            return .object(Dictionary(uniqueKeysWithValues: values.map { key, nested in
                (key, scaledJSONValue(nested, by: scale))
            }))
        case .string, .bool, .null:
            return value
        }
    }

    mutating func apply(riven: Riven, notes: inout [String]) {
        if let v = riven.damage { damageBonus += v }
        if let v = riven.multishot { multishot += v }
        if let v = riven.critChance { critChanceRelative += v }
        if let v = riven.critDamage { critDamageRelative += v }
        if let v = riven.statusChance { statusChanceRelative += v }
        if let v = riven.statusDuration { statusDuration += v }
        if let v = riven.fireRate { fireRate += v }
        if let v = riven.reloadSpeed { reloadSpeed += v }
        if let v = riven.magazineSize { magazine += v }
        if let v = riven.meleeComboEfficiency { meleeComboEfficiency += v }
        if let v = riven.faction { anyFactionBonus += v }
        for (rawFaction, value) in riven.factionBonuses ?? [:] {
            let key = FactionProfile.resolve(rawFaction: rawFaction).canonical
            faction[key] = max(faction[key] ?? 0, value)
        }
        for (k, v) in riven.elements ?? [:] {
            if let t = DamageType(dataKey: k) { elements.append((t, v)) }
        }
        for (k, v) in riven.physical ?? [:] {
            if let t = DamageType(dataKey: k) { physical[t, default: 0] += v }
        }
    }

    /// 应用任意环境来源已经明确给出的数值。这里没有名称分支，因此 Roar、队友
    /// 光环或尚未导入数据表的宠物效果都能以同一套伤害池进入计算。
    mutating func apply(externalBuff buff: ExternalWeaponBuff) {
        damageBonus += buff.damageBonus
        critChanceRelative += buff.critChanceBonus
        critDamageAbsolute += buff.critDamageBonus
        multishot += buff.multishotBonus
        fireRate += buff.fireRateBonus
        reloadSpeed += buff.reloadSpeedBonus
        statusChanceRelative += buff.statusChanceBonus
        statusDuration += buff.statusDurationBonus
        statusDamage += buff.statusDamageBonus
        anyFactionBonus += buff.factionBonus
        for (rawType, value) in buff.elements {
            if let type = DamageType(dataKey: rawType) {
                externalElements.append((type, value))
            }
        }
        for (rawType, value) in buff.statusElementBonuses {
            if let type = DamageType(dataKey: rawType) {
                externalDotElementBonuses.append((type, value))
            }
        }
    }

    /// 外部来源主动选择的数据表 Mod。与武器槽位不同，它允许 frame_mod；条件值
    /// 由 ExternalEffectSource 明确提供，缺失时不把条件效果臆测为已生效。
    mutating func apply(externalMod mod: ModDefinition, source effect: ExternalEffectSource,
                        weapon: Weapon, attack: Attack, options: Options, notes: inout [String]) {
        var action = mod.action ?? [:]
        // A source can carry its caster-specific Ability Strength and, when
        // relevant, the exact equipped rank of its augment.  Falling back to
        // Options keeps saved website-style inputs compatible, but clients
        // with a concrete Warframe source must not borrow another caster's
        // strength or silently promote an augment to max rank.
        let abilityStrength = max(0, effect.abilityStrength ?? options.abilityStrength)
            * max(0, effect.effectScale ?? 1)
        if let perWeapon = action.removeValue(forKey: "FOR_WEAPON")?.objectValue {
            for (tag, raw) in perWeapon where Self.weapon(weapon, matches: tag) {
                for (key, value) in raw.objectValue ?? [:] { action[key] = value }
            }
        }
        let conditional = action.removeValue(forKey: "WITH_COND")?.objectValue
        extractExternalElementActions(&action, abilityStrength: abilityStrength)
        // 这两个键是同类 DOT 的元素伤害倍率，和前面的直接附伤不是一回事。
        if let value = action.removeValue(forKey: "electricity_scaledByStrength")?.doubleValue {
            externalDotElementBonuses.append((.electricity, value * abilityStrength))
        }
        if let value = action.removeValue(forKey: "heat_scaledByStrength")?.doubleValue {
            externalDotElementBonuses.append((.heat, value * abilityStrength))
        }
        mutatingApply(action: action, modName: mod.name, source: .mod, notes: &notes)

        guard let conditional, !conditional.isEmpty else { return }
        let conditionValue = effect.conditionValue
            ?? options.conditionalStackCount(named: mod.name)
        guard conditionValue > 0 else { return }
        applyExternalConditional(conditional, value: conditionValue, notes: &notes)
    }

    /// 从外部 Mod action 抽出“武器元素合并之后添加”的赋能。所有 `...S` 和
    /// `NotCombined` 形式都是站点数据对这类来源的明确标识。
    private mutating func extractExternalElementActions(_ action: inout [String: JSONValue],
                                                        abilityStrength: Double) {
        let strength = abilityStrength
        let scaled: [(String, DamageType, Bool)] = [
            ("addHeatNotCombined", .heat, false),
            ("addElectricityNotCombined", .electricity, false),
            ("addColdNotCombined", .cold, false),
            ("addToxinNotCombined", .toxin, false),
            ("addHeatNotCombinedScaledByStrength", .heat, true),
            ("addElectricityNotCombinedScaledByStrength", .electricity, true),
            ("addColdNotCombinedScaledByStrength", .cold, true),
            ("addToxinNotCombinedScaledByStrength", .toxin, true),
            ("addViralS", .viral, true),
            ("addCorrosiveS", .corrosive, true),
            ("addRadiationS", .radiation, true),
            ("addMagneticS", .magnetic, true),
            ("addGasS", .gas, true),
            ("addBlastS", .blast, true)
        ]
        for (key, type, scalesWithStrength) in scaled {
            guard let value = action.removeValue(forKey: key)?.doubleValue else { continue }
            externalElements.append((type, value * (scalesWithStrength ? strength : 1)))
        }
    }

    private static func weapon(_ weapon: Weapon, matches rawTag: String) -> Bool {
        let tag = BuildResolver.normalize(rawTag)
        var keys = Set<String>()
        keys.insert(BuildResolver.normalize(weapon.name))
        for value in weapon.categories ?? [] { keys.insert(BuildResolver.normalize(value)) }
        for value in weapon.compTags ?? [] { keys.insert(BuildResolver.normalize(value)) }
        if let value = weapon.category { keys.insert(BuildResolver.normalize(value)) }
        if let value = weapon.type { keys.insert(BuildResolver.normalize(value)) }
        return keys.contains(tag)
    }

    /// 条件 action 的数值由调用方传入的当前条件值线性缩放。这个路径覆盖数据表
    /// 中的 Tek Collateral、Tenacious Bond、Reinforced Bond、Vigorous Swap、
    /// Smoke Shadow、Biting Frost 以及 Gladiator 每 combo 项；未知键仍会进入
    /// 通常的 unsupported 报告，绝不静默套用。
    private mutating func applyExternalConditional(_ conditional: [String: JSONValue],
                                                   value: Double, notes: inout [String]) {
        var scaled: [String: JSONValue] = [:]
        for (key, raw) in conditional {
            guard let number = raw.doubleValue else {
                unsupported.insert("WITH_COND.\(key)")
                continue
            }
            switch key {
            case "crit_chance_per_combo":
                scaled["crit_chance"] = .number(number * value)
            default:
                scaled[key] = .number(number * value)
            }
        }
        mutatingApply(action: scaled, modName: nil, source: .mod, notes: &notes)
    }

    mutating func apply(conditional: [String: JSONValue], staticAction: [String: JSONValue],
                        modName: String, rule: ConditionalEffectRule?, attack: Attack? = nil,
                        options: Options, conditionalStepScale: Double? = nil,
                        notes: inout [String]) {
        let inputCount = max(0, options.conditionalStackCount(named: modName))
        let stepScale: Double
        if let conditionalStepScale {
            guard conditionalStepScale.isFinite, conditionalStepScale >= 0 else {
                notes.append("已忽略无效的条件单次倍率: \(modName)")
                return
            }
            stepScale = conditionalStepScale
        } else {
            stepScale = 1
        }
        // `inputCount` is the actual in-game count picked in the UI (for
        // example, ability casts). A lower-ranked card can grant less per
        // input while retaining the source card's final cap.
        let effectiveStacks = inputCount * stepScale
        var handled = Set<String>()

        // 原始站点数据只给出 `WITH_COND` 的满层数字，未标记它是“总值”还是
        // “额外值”。这个差别在 conditional-effects.json 声明；解析器只消费规则
        // 类型与参数，不根据某张 Mod 的名字进入不同公式。
        if let rule, rule.maxStacks > 0 {
            let scale = min(effectiveStacks, rule.maxStacks) / rule.maxStacks
            for key in rule.keys {
                guard let maximum = conditional[key]?.doubleValue else { continue }
                let value: Double
                switch rule.mode {
                case .totalRelativeToStaticAction:
                    guard let staticValue = staticAction[key]?.doubleValue else {
                        unsupported.insert("WITH_COND.\(key) 缺少普通 action 基值")
                        continue
                    }
                    value = (maximum - staticValue) * scale
                case .scaledConditionalValue:
                    value = maximum * scale
                }

                if key == "charge_time" {
                    // 这项是相对现有蓄力时间的修正；非蓄力攻击段不伪造一条时间。
                    if attack?.chargeTime != nil { chargeTimeBonus += value }
                } else {
                    mutatingApply(action: [key: .number(value)], modName: modName,
                                  source: .mod, notes: &notes)
                }
                handled.insert(key)
            }
        }

        // The website's global “all Mod conditions are met” switch turns an
        // otherwise unlisted binary WITH_COND action on at its literal value.
        // Stack-based cards above still use their explicit source-data rule;
        // for the rest, applying the raw action is both more faithful and less
        // error-prone than a Mod-name list in the UI.  When the global switch
        // is off, those conditions remain off rather than being mislabeled as
        // unsupported formulas.
        var enabledBinaryActions: [String: JSONValue] = [:]
        for (key, value) in conditional where !handled.contains(key) {
            let v = value.doubleValue ?? 0
            switch key {
            case "headshot_mult":
                if options.allModConditionsMet && options.weakPoint {
                    weakPointHeadshotBonus += v
                }
            case "crit_chance_weakp":
                // Weak-point critical chance is a relative base-crit bonus. It
                // shares the additive pool with Point Strike rather than adding
                // percentage points after that pool.
                if options.allModConditionsMet && options.weakPoint {
                    critChanceWeakPoint += v
                }
            case "set_mutishot_to_default":
                if options.allModConditionsMet { locksMultishot = true }
            default:
                if options.allModConditionsMet { enabledBinaryActions[key] = value }
            }
        }
        if !enabledBinaryActions.isEmpty {
            mutatingApply(action: enabledBinaryActions, modName: modName,
                          source: .mod, notes: &notes)
        }
    }

    mutating func apply(json: [String: JSONValue], from source: Source, notes: inout [String]) {
        mutatingApply(action: json, modName: nil, source: source, notes: &notes)
    }

    /// 从数据表注册一项 CO 风格伤害；当表缺失语义时，宁可把它记为未实现，
    /// 也不把某张 Mod 静默当成常驻或满层。
    private mutating func registerPerStatusDamage(valueAtFullEffect: Double, modName: String,
                                                  rule: ConditionalEffectRule?,
                                                  notes: inout [String]) {
        guard let semantics = rule?.perStatusDamage else {
            unsupported.insert("base_per_status 缺少规则: \(modName)")
            return
        }
        let excluded = Set(semantics.excludedShotTypes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        perStatusDamageEffects.append(PerStatusDamageEffect(
            mod: modName,
            valueAtFullEffect: valueAtFullEffect,
            maxStacks: rule?.maxStacks ?? 0,
            activation: semantics.activation,
            excludedShotTypes: excluded
        ))
    }

    /// 对一段攻击求目标每种状态给予的 CO/Gun CO 系数。这个函数只读规则
    /// 数据，不包含 Mod 名称、预设层数或攻击类型的专用判断。
    func directDamagePerStatusType(for attack: Attack, options: Options) -> Double {
        let shotType = attack.shotType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var total = perStatusDamageEffects.reduce(0) { total, effect in
            if let shotType, effect.excludedShotTypes.contains(shotType) {
                return total
            }
            let scale: Double
            switch effect.activation {
            case .always:
                scale = 1
            case .conditionalStacks:
                guard effect.maxStacks > 0 else { return total }
                let stacks = min(max(options.conditionalStackCount(named: effect.mod), 0),
                                 effect.maxStacks)
                scale = stacks / effect.maxStacks
            }
            return total + effect.valueAtFullEffect * scale
        }
        // The website's custom `base_per_status` participates only while its
        // global “all Mod conditions” switch is enabled, and excludes AoE and
        // Slam attacks in the same place as its own Gun-CO calculation.
        let isAOE = shotType == "aoe"
        let isSlam = attack.name.range(of: "slam", options: .caseInsensitive) != nil
        if options.allModConditionsMet, !isAOE, !isSlam {
            total += options.customStat(.basePerStatus)
        }
        return total
    }

    private mutating func mutatingApply(action: [String: JSONValue], modName: String?,
                                        source: Source, notes: inout [String]) {
        var marks: Set<String> = []
        for (key, value) in action {
            let v = value.doubleValue
            switch key {
            case "base":
                // mod 的 `base` 是 +伤害%（Serration 1.65），彼此加算；
                // 灵化的 `base` 同样是 +伤害%，走同一条加算池。
                damageBonus += v ?? 0
            case "element":
                for (k, num) in value.objectValue ?? [:] {
                    if let t = DamageType(dataKey: k), let n = num.doubleValue { elements.append((t, n)) }
                }
            case "phys":
                for (k, num) in value.objectValue ?? [:] {
                    if let t = DamageType(dataKey: k), let n = num.doubleValue { physical[t, default: 0] += n }
                }
            case "crit_chance":
                critChanceRelative += v ?? 0
            case "crit_chance_per_combo":
                critChancePerCombo += v ?? 0
            // 灵化："Increase Base Critical Chance by +20%" —— 加在**基础**暴击率上的
            // 绝对百分点，不是相对百分比。`add_` / `flat_` 两个前缀是同一件事的两个写法。
            // 来源：<https://wiki.warframe.com/w/Torid>（EVO4 Commodore's Fortune / Survivor's Edge）
            case "add_crit_chance", "flat_crit_chance":
                critChanceAbsolute += v ?? 0
            // 灵化："Increase Base Critical Damage Multiplier by +2x"，值是倍率的绝对增量。
            case "flat_critmult", "crit_mult_add":
                critDamageAbsolute += v ?? 0
            case "crit_mult":
                critDamageRelative += v ?? 0
            case "heavy_crit_mult":
                heavyCritDamageRelative += v ?? 0
            // Laetum / Phenmor 类灵化：在未暴击的那一份命中中，按 chance 概率
            // 增加 value 倍基础伤害。它不属于普通的加法 base 伤害池。
            case "base_noncrit":
                let data = value.objectValue ?? [:]
                nonCriticalDamageBonus += data["value"]?.doubleValue ?? 0
                nonCriticalDamageChance = max(nonCriticalDamageChance,
                                              min(max(data["chance"]?.doubleValue ?? 0, 0), 1))
            case "add_slash":
                slashOnCriticalChance += v ?? 0
            case "base_per_status":
                // 武器槽位上的此字段已在 `apply(mod:...)` 中连同其数据表语义
                // 注册；来自其它 JSON 入口却没有规则时不可擅自套用。
                marks.insert(key)
            case "status_chance":
                statusChanceRelative += v ?? 0
            case "status_chance_by_combo":
                statusChancePerCombo += v ?? 0
            case "h_status_chance":
                heavyStatusChanceRelative += v ?? 0
            // 灵化："Increase Base Status Chance by +34%"，同样是绝对百分点。
            case "flat_status_chance":
                statusChanceAbsolute += v ?? 0
            case "absolute_status_chance":
                statusChanceAbsolute += (v ?? 0) / 100
            case "multishot":
                multishot += v ?? 0
            // 灵化："+2 Multishot"，直接加多发弹丸。
            case "flat_multishot":
                multishotAbsolute += v ?? 0
            // 灵化："+3 Multishot on last shot in magazine"，只作用于弹匣最后一发。
            case "l_add_multishot":
                lastShotMultishot += v ?? 0
            case "double_crit":
                doubleCritChance += v ?? 0
            // 灵化："Increase Base Damage by +51"，加在基础伤害上的固定值。
            case "flat_change_dmg":
                flatDamage += v ?? 0
            case "flat_change_dmg_by_strength":
                flatDamageByAbilityStrength += v ?? 0
            case "speed":
                fireRate += v ?? 0
            case "reloadTime":
                reloadSpeed += v ?? 0
            case "magazineSize":
                magazine += v ?? 0
            // 灵化："Increase Base Magazine Capacity by +9"，加在基础弹匣上的固定值。
            case "add_magazineSize":
                flatMagazine += v ?? 0
            case "status_damage":
                statusDamage += v ?? 0
            case "h_status_damage":
                heavyStatusDamage += v ?? 0
            case "vuln_status_damage":
                // Burning Hate and similar actions depend on a pre-existing target
                // status.  Build resolution has no target-state predicate, so do
                // not silently treat this as an unconditional Elementalist bonus.
                marks.insert(key)
            case "status_damage_slash":
                statusDamageByType[.slash, default: 0] += v ?? 0
            case "status_damage_heat":
                statusDamageByType[.heat, default: 0] += v ?? 0
            case "status_damage_electricity":
                statusDamageByType[.electricity, default: 0] += v ?? 0
            case "status_damage_toxin":
                statusDamageByType[.toxin, default: 0] += v ?? 0
            case "status_damage_gas":
                statusDamageByType[.gas, default: 0] += v ?? 0
            case "status_duration":
                statusDuration += v ?? 0
            case "incMaxStacks_Corrosion":
                corrosiveStackCapBonus += max(0, v ?? 0)
            case "SMITE":
                for (factionName, num) in value.objectValue ?? [:] {
                    // 站点数据把母派系和子派系都列了一遍（`Grineer` / `Kuva Grineer`），
                    // 归一化后会撞到同一个 key，这里取最大值而不是累加。
                    let key = FactionProfile.resolve(rawFaction: factionName).canonical
                    let value = num.doubleValue ?? 0
                    faction[key] = max(faction[key] ?? 0, value)
                }
            case "mult_for_head":
                headshotBonus += v ?? 0
            case "charge_time":
                chargeTimeBonus += v ?? 0
            case "base_heavy":
                heavyDamageBonus += v ?? 0
            case "initialCombo":
                initialComboPoints += v ?? 0
            case "melee_combo_eff":
                meleeComboEfficiency += v ?? 0
            case "windUp":
                windUpSpeed += v ?? 0
            case "addViral":
                if let v { elements.append((.viral, v)) }
            case "addMagnetic":
                if let v { elements.append((.magnetic, v)) }
            case "addRadiation":
                if let v { elements.append((.radiation, v)) }
            // Melee Exposure grants a completed Corrosive component after an
            // ability cast. It is not two adjacent slot elements, so preserve
            // it as its own combined type in the slot-order merge.
            case "addCorrosive":
                if let v { elements.append((.corrosive, v)) }
            // Stance combo entries are parsed by `MeleeStanceLibrary` after
            // Mod-slot validation.  They are not a damage-stat action here.
            case "stances":
                break
            case "set_speed_to_default":
                locksFireRate = true
            // 这些属性不会改变单目标、命中已经成立时的一发伤害、状态或换弹时间；
            // 不把它们伪装成“未实现的伤害机制”。
            case "recoil", "zoom", "accuracy", "spread", "range", "blast_radius", "d_sound",
                 "beam_length", "shot_speed", "lifesteal", "punch_through", "ammoCapacity",
                 "set_ammoCapacity", "ammoEff", "ammoEffFull":
                break
            case "FOR_WEAPON", "WITH_COND", "set", "unique", "force_procs", "mutator", "na",
                 "comboDuration", "slam_mult",
                  "finisherDmg", "add_slash_on_impact", "electricityBonus",
                 "comboIn", "f_multiple",
                 "electricityShardAbilityDmg", "purity", "sobekAug", "addViral2":
                marks.insert(key)
            default:
                marks.insert(key)
            }
        }
        switch source {
        case .mod: unsupported.formUnion(marks)
        case .incarnon: unsupportedIncarnon.formUnion(marks)
        }
    }
}
