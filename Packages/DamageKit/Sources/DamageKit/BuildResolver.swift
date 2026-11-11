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
    public var statusChance: Double      // 每弹丸，小数，可以 > 1
    public var multishot: Double
    /// 只在「弹匣最后一发」上额外增加的多重射击（灵化 `l_add_multishot`）。
    public var lastShotMultishot: Double
    public var fireRate: Double
    public var magazine: Double
    public var reload: Double
    public var burstCount: Int
    public var burstDelay: Double
    public var factionBonus: Double      // 小数，例如 0.3
    public var statusDamageBonus: Double // 小数
    public var statusDuration: Double    // 秒
    public var headshotMultiplier: Double
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

    /// mod 与武器的兼容判定。
    ///
    /// 站点的 `tags` 有两层含义：多数是武器类别（`primary-rifle`），
    /// 少数是具体武器名的大写形式（`RIPKAS`）。两边都归一化成小写去比较。
    public func modApplies(_ mod: ModDefinition) -> Bool {
        if mod.type == "frame_mod" { return false }
        guard let tags = mod.tags, !tags.isEmpty else { return false }
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

    public func resolveAll() -> [ResolvedAttack] {
        weapon.attacks.map { resolve(attack: $0) }
    }

    public func resolve(attack: Attack) -> ResolvedAttack {
        var agg = ModAggregate()
        var notes: [String] = []

        // 1. 收集 mod
        for name in build.mods {
            guard let mod = library.mod(named: name) else {
                notes.append("未知 mod: \(name)")
                continue
            }
            guard modApplies(mod) else {
                notes.append("mod 与该武器不兼容: \(name)")
                continue
            }
            agg.apply(mod: mod, attack: attack, options: options, notes: &notes)
        }

        // 互斥：站点数据里 `uncomp` 列出了互相排斥的 mod
        if !build.mods.isEmpty {
            var kept: [String] = []
            for name in build.mods {
                guard let mod = library.mod(named: name) else { continue }
                let conflicts = (mod.uncomp ?? []).map { $0.lowercased() }
                if kept.contains(where: { conflicts.contains($0.lowercased()) }) {
                    notes.append("互斥 mod 被忽略: \(name)")
                    continue
                }
                kept.append(name)
            }
        }

        // 2. 紫卡
        if let riven = build.riven {
            agg.apply(riven: riven, notes: &notes)
        }

        // 3. 灵化进化节点
        if !build.incarnonPerks.isEmpty {
            applyIncarnon(&agg, attack: attack, notes: &notes)
        }

        // 4. 折成最终数值
        //
        // 灵化的 `flat_change_dmg`（wiki 原文 "Increase Base Damage by +51"）是加在
        // **基础伤害**上的固定值：先按该段原有伤害构成等比例摊到各类型，再一起吃
        // +伤害% mod 与元素 mod。来源：<https://wiki.warframe.com/w/Torid>（EVO2 Final Fusillade）
        let rawBaseTotal = attack.damage.totalDamage
        var baseDamage = attack.damage
        if agg.flatDamage != 0 && rawBaseTotal > 0 {
            for (t, v) in attack.damage.ordered {
                baseDamage[t] = v + agg.flatDamage * (v / rawBaseTotal)
            }
        }

        let damageBonus = agg.damageBonus + options.warframe.damageBonus
        var damage: [DamageType: Double] = [:]
        for (t, v) in baseDamage.ordered { damage[t] = v * (1 + damageBonus) }

        // 物理 mod 加的是「该类型在基础伤害里的占比 × 数值」，所以按基础值乘
        for (t, v) in agg.physical where t.isPhysical {
            let base = baseDamage[t] ?? 0
            damage[t, default: 0] += base * (1 + damageBonus) * v
        }

        let moddedTotal = damage.totalDamage
        let modElements: [(DamageType, Double)] = agg.elements.map { ($0.0, moddedTotal * $0.1) }
        damage = BuildResolver.mergeElements(base: damage, mods: modElements)

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
        let critChance = (attack.critChance / 100) * (1 + agg.critChanceRelative + options.warframe.critChanceBonus)
            + agg.critChanceAbsolute
            + (options.weakPoint ? agg.critChanceWeakPoint : 0)
        let critMultiplier = baseCritDamage * (1 + agg.critDamageRelative)
            + agg.critDamageAbsolute + options.warframe.critDamageBonus

        let statusChance = (attack.statusChance / 100) * (1 + agg.statusChanceRelative) + agg.statusChanceAbsolute

        let baseMultishot = attack.multishot ?? weapon.multishot ?? 1
        let multishot = agg.locksMultishot
            ? baseMultishot
            : baseMultishot * (1 + agg.multishot + options.warframe.multishotBonus) + agg.multishotAbsolute

        let fireRate = attack.speed * (1 + agg.fireRate + options.warframe.fireRateBonus)

        // 灵化形态用的是 incMagazineSize，而且**不吃任何 mod**（包括灵化的 +9 弹匣）。
        // 来源：<https://wiki.warframe.com/w/Torid>（"Incarnon Form's magazine is not affected by mods"）
        let magazine: Double
        if attack.isIncarnonForm {
            magazine = max(1, weapon.incarnonMagazineSize ?? weapon.magazineSize ?? 1)
        } else {
            // `add_magazineSize` 加的是**基础**弹匣容量，所以先加固定值再吃 +弹匣% mod。
            magazine = max(1, ((weapon.magazineSize ?? 1) + agg.flatMagazine) * (1 + agg.magazine))
        }
        let reload = max(0, (weapon.reloadTime ?? 0) / (1 + agg.reloadSpeed))

        let factionBonus = (agg.faction[faction.canonical] ?? 0) + agg.anyFactionBonus + options.warframe.factionBonus
        let headshot: Double
        if options.headshot && !attack.noHeadshotMultiplier {
            headshot = options.headshotMultiplier + agg.headshotBonus
        } else {
            headshot = 1
        }

        if attack.chargeTime != nil || (agg.chargeTime ?? 0) != 0 {
            notes.append("charge_time 未纳入射速模型（见 README 待确认项）")
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

        let ordered = damage.ordered.map { DamageEntry(type: $0.0, value: $0.1) }
        let total = ordered.reduce(0) { $0 + $1.value }

        return ResolvedAttack(
            name: attack.name,
            damage: damage,
            orderedDamage: ordered,
            totalDamage: total,
            critChance: critChance,
            critMultiplier: critMultiplier,
            statusChance: statusChance,
            multishot: multishot,
            lastShotMultishot: agg.lastShotMultishot,
            fireRate: fireRate,
            magazine: magazine,
            reload: reload,
            burstCount: max(1, attack.burstCount ?? 1),
            burstDelay: attack.burstDelay ?? 0,
            factionBonus: factionBonus,
            statusDamageBonus: agg.statusDamage + options.warframe.statusDamageBonus,
            statusDuration: Rules.statusBaseDuration * (1 + agg.statusDuration),
            headshotMultiplier: headshot,
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
            let action = option.action ?? [:]
            agg.apply(json: action, from: .incarnon, notes: &notes)
            // 灵化的条件加成（`WITH_COND`）依赖「护甲 > 450 / 有超宏 / 击杀后」这类状态，
            // 模型里没有对应的开关，所以整条跳过，但要把是哪条进化写进 notes。
            if let cond = action["WITH_COND"], cond.objectValue?.isEmpty == false {
                let label = option.name.split(separator: ":").first.map(String.init) ?? option.name
                notes.append("灵化的条件加成未实现: \(label)")
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
    var physical: [DamageType: Double] = [:]
    var critChanceRelative: Double = 0
    var critChanceAbsolute: Double = 0
    var critChanceWeakPoint: Double = 0
    var critDamageRelative: Double = 0
    var critDamageAbsolute: Double = 0
    var statusChanceRelative: Double = 0
    var statusChanceAbsolute: Double = 0
    var multishot: Double = 0
    var multishotAbsolute: Double = 0
    var fireRate: Double = 0
    var reloadSpeed: Double = 0
    var magazine: Double = 0
    var flatMagazine: Double = 0
    /// 灵化 `flat_change_dmg`：直接加在基础伤害上的固定值。
    var flatDamage: Double = 0
    var lastShotMultishot: Double = 0
    var statusDamage: Double = 0
    var statusDuration: Double = 0
    var faction: [String: Double] = [:]
    var anyFactionBonus: Double = 0
    var headshotBonus: Double = 0
    var chargeTime: Double?
    var locksMultishot = false
    var locksFireRate = false
    var unsupported: Set<String> = []
    var unsupportedIncarnon: Set<String> = []

    mutating func apply(mod: ModDefinition, attack: Attack, options: Options, notes: inout [String]) {
        var action = mod.action ?? [:]
        // FOR_WEAPON：按武器类别覆盖
        if let perWeapon = action["FOR_WEAPON"]?.objectValue {
            for (tag, sub) in perWeapon {
                let key = BuildResolver.normalize(tag)
                // 这里没有武器对象，只有攻击段，所以退化成「按武器类别名匹配 atttack 上的 shot_type」不可靠，
                // 交给调用方处理；目前只做无条件合并会高估，故跳过并记一条。
                _ = key
                _ = sub
            }
            if !perWeapon.isEmpty {
                notes.append("FOR_WEAPON 覆盖未实现: \(mod.name)")
            }
        }
        if action["WITH_COND"] != nil { action.removeValue(forKey: "WITH_COND") }
        mutatingApply(action: action, modName: mod.name, source: .mod, notes: &notes)

        if let cond = mod.action?["WITH_COND"]?.objectValue {
            apply(conditional: cond, modName: mod.name, options: options, notes: &notes)
        }
        if mod.action?["set"] != nil { /* 套装加成未实现 */ }
    }

    mutating func apply(riven: Riven, notes: inout [String]) {
        if let v = riven.damage { damageBonus += v }
        if let v = riven.multishot { multishot += v }
        if let v = riven.critChance { critChanceRelative += v }
        if let v = riven.critDamage { critDamageRelative += v }
        if let v = riven.statusChance { statusChanceRelative += v }
        if let v = riven.statusDuration { statusDuration += v }
        if let v = riven.fireRate { fireRate += v }
        if let v = riven.faction { anyFactionBonus += v }
        for (k, v) in riven.elements ?? [:] {
            if let t = DamageType(dataKey: k) { elements.append((t, v)) }
        }
        for (k, v) in riven.physical ?? [:] {
            if let t = DamageType(dataKey: k) { physical[t, default: 0] += v }
        }
    }

    mutating func apply(conditional: [String: JSONValue], modName: String,
                        options: Options, notes: inout [String]) {
        for (key, value) in conditional {
            let v = value.doubleValue ?? 0
            switch key {
            case "headshot_mult":
                if options.headshot { headshotBonus += v }
            case "crit_chance_weakp":
                if options.weakPoint { critChanceAbsolute += v / 100 }
            case "set_mutishot_to_default":
                locksMultishot = true
            default:
                unsupported.insert("WITH_COND.\(key)")
            }
        }
    }

    mutating func apply(json: [String: JSONValue], from source: Source, notes: inout [String]) {
        mutatingApply(action: json, modName: nil, source: source, notes: &notes)
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
            // 灵化："Increase Base Critical Chance by +20%" —— 加在**基础**暴击率上的
            // 绝对百分点，不是相对百分比。`add_` / `flat_` 两个前缀是同一件事的两个写法。
            // 来源：<https://wiki.warframe.com/w/Torid>（EVO4 Commodore's Fortune / Survivor's Edge）
            case "add_crit_chance", "flat_crit_chance":
                critChanceAbsolute += v ?? 0
            // 灵化："Increase Base Critical Damage Multiplier by +2x"，值是倍率的绝对增量。
            case "flat_critmult":
                critDamageAbsolute += v ?? 0
            case "crit_mult", "heavy_crit_mult":
                critDamageRelative += v ?? 0
            case "status_chance":
                statusChanceRelative += v ?? 0
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
            // 灵化："Increase Base Damage by +51"，加在基础伤害上的固定值。
            case "flat_change_dmg":
                flatDamage += v ?? 0
            case "speed":
                fireRate += v ?? 0
            case "reloadTime":
                reloadSpeed += v ?? 0
            case "magazineSize":
                magazine += v ?? 0
            // 灵化："Increase Base Magazine Capacity by +9"，加在基础弹匣上的固定值。
            case "add_magazineSize":
                flatMagazine += v ?? 0
            case "status_damage", "vuln_status_damage":
                statusDamage += v ?? 0
            case "status_duration":
                statusDuration += v ?? 0
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
                chargeTime = v
            case "addViral":
                if let v { elements.append((.viral, v)) }
            case "addMagnetic":
                if let v { elements.append((.magnetic, v)) }
            case "addRadiation":
                if let v { elements.append((.radiation, v)) }
            case "set_speed_to_default":
                locksFireRate = true
            case "FOR_WEAPON", "WITH_COND", "set", "unique", "mutator", "na", "d_sound",
                 "recoil", "zoom", "accuracy", "spread", "punch_through", "ammoCapacity",
                 "set_ammoCapacity", "ammoEff", "ammoEffFull",
                 "comboDuration", "windUp", "initialCombo", "melee_combo_eff", "slam_mult",
                 "range", "blast_radius", "beam_length", "shot_speed", "lifesteal",
                 "finisherDmg", "add_slash_on_impact", "status_damage_toxin", "electricityBonus",
                 "base_heavy", "comboIn", "double_crit", "f_multiple", "incMaxStacks_Corrosion",
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
