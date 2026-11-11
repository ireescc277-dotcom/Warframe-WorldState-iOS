import Foundation

// MARK: - 武器

/// 一段攻击。一把武器可能有多段（直击 / 爆炸 / 毒云 / 灵化形态……），
/// 每段独立成账，见 README「计算口径」第 2 条。
public struct Attack: Codable, Sendable, Equatable {
    public var name: String
    /// 每秒发数。
    public var speed: Double
    /// 百分比，15 表示 15%。
    public var critChance: Double
    public var critMultiplier: Double
    /// 百分比。
    public var statusChance: Double
    public var damage: [DamageType: Double]
    public var shotType: String?
    /// AoE 段不吃爆头倍率。
    public var noHeadshotMultiplier: Bool
    public var multishot: Double?
    public var burstCount: Int?
    public var burstDelay: Double?
    public var chargeTime: Double?
    public var falloff: Falloff?
    public var isIncarnonForm: Bool
    public var isBeam: Bool
    public var hasConditionalMultishot: Bool
    public var radius: Double?
    public var forceProcs: [String: Double]?
    /// 数据里的 `unique` 一律是对象（全库 423 处都是 dict，没有一处是字符串），
    /// 例如 `{"force_procs": ["impact"]}`。按原始 JSON 存下来，不猜结构。
    public var unique: [String: JSONValue]?

    public struct Falloff: Codable, Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var reduction: Double
    }

    public init(
        name: String,
        speed: Double,
        critChance: Double,
        critMultiplier: Double,
        statusChance: Double,
        damage: [DamageType: Double],
        shotType: String? = nil,
        noHeadshotMultiplier: Bool = false,
        multishot: Double? = nil,
        burstCount: Int? = nil,
        burstDelay: Double? = nil,
        chargeTime: Double? = nil,
        falloff: Falloff? = nil,
        isIncarnonForm: Bool = false,
        isBeam: Bool = false,
        hasConditionalMultishot: Bool = false,
        radius: Double? = nil,
        forceProcs: [String: Double]? = nil,
        unique: [String: JSONValue]? = nil
    ) {
        self.name = name
        self.speed = speed
        self.critChance = critChance
        self.critMultiplier = critMultiplier
        self.statusChance = statusChance
        self.damage = damage
        self.shotType = shotType
        self.noHeadshotMultiplier = noHeadshotMultiplier
        self.multishot = multishot
        self.burstCount = burstCount
        self.burstDelay = burstDelay
        self.chargeTime = chargeTime
        self.falloff = falloff
        self.isIncarnonForm = isIncarnonForm
        self.isBeam = isBeam
        self.hasConditionalMultishot = hasConditionalMultishot
        self.radius = radius
        self.forceProcs = forceProcs
        self.unique = unique
    }

    private enum CodingKeys: String, CodingKey {
        case name, speed, damage, multishot, radius, unique, falloff
        case critChance = "crit_chance"
        case critMultiplier = "crit_mult"
        case statusChance = "status_chance"
        case shotType = "shot_type"
        case noHeadshotMultiplier = "no_headshot_mult"
        case burstCount = "burst_count"
        case burstDelay = "burst_delay"
        case chargeTime = "charge_time"
        case isIncarnonForm = "isInc"
        case isBeam = "isBeam"
        case hasConditionalMultishot = "isCoMult"
        case forceProcs = "force_procs"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Attack"
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        critChance = try c.decodeIfPresent(Double.self, forKey: .critChance) ?? 0
        critMultiplier = try c.decodeIfPresent(Double.self, forKey: .critMultiplier) ?? 1
        statusChance = try c.decodeIfPresent(Double.self, forKey: .statusChance) ?? 0
        shotType = try c.decodeIfPresent(String.self, forKey: .shotType)
        noHeadshotMultiplier = try c.decodeIfPresent(Bool.self, forKey: .noHeadshotMultiplier) ?? false
        multishot = try c.decodeIfPresent(Double.self, forKey: .multishot)
        burstCount = try c.decodeIfPresent(Int.self, forKey: .burstCount)
        burstDelay = try c.decodeIfPresent(Double.self, forKey: .burstDelay)
        chargeTime = try c.decodeIfPresent(Double.self, forKey: .chargeTime)
        falloff = try c.decodeIfPresent(Falloff.self, forKey: .falloff)
        isIncarnonForm = (try c.decodeIfPresent(Int.self, forKey: .isIncarnonForm) ?? 0) != 0
        isBeam = try c.decodeIfPresent(Bool.self, forKey: .isBeam) ?? false
        hasConditionalMultishot = try c.decodeIfPresent(Bool.self, forKey: .hasConditionalMultishot) ?? false
        radius = try c.decodeIfPresent(Double.self, forKey: .radius)
        forceProcs = try c.decodeIfPresent([String: Double].self, forKey: .forceProcs)
        unique = try c.decodeIfPresent([String: JSONValue].self, forKey: .unique)
        damage = try Attack.decodeDamage(from: c)
    }

    /// 数据里 `damage` 绝大多数是 `{ "toxin": 100 }`，
    /// 少数武器（Simulor 系）是多个伤害字典的数组，按段相加。
    private static func decodeDamage(from c: KeyedDecodingContainer<CodingKeys>) throws -> [DamageType: Double] {
        if let dict = try? c.decodeIfPresent([String: Double].self, forKey: .damage) {
            var out: [DamageType: Double] = [:]
            for (k, v) in dict {
                guard let t = DamageType(dataKey: k) else { continue }
                out[t, default: 0] += v
            }
            return out
        }
        if let list = try? c.decodeIfPresent([[String: Double]].self, forKey: .damage) {
            var out: [DamageType: Double] = [:]
            for dict in list {
                for (k, v) in dict {
                    guard let t = DamageType(dataKey: k) else { continue }
                    out[t, default: 0] += v
                }
            }
            return out
        }
        return [:]
    }
}

public struct Weapon: Codable, Sendable, Equatable {
    public var name: String
    public var category: String?
    public var type: String?
    public var masteryReq: Int?
    public var magazineSize: Double?
    public var incarnonMagazineSize: Double?
    public var reloadTime: Double?
    public var multishot: Double?
    public var trigger: String?
    public var attacks: [Attack]
    /// 同一次开火会同时产生的攻击段，例如 `[[0, 1]]` 表示第 0、1 段一起出。
    public var comb: [[Int]]?
    public var tags: [String]?
    public var categories: [String]?
    public var compTags: [String]?
    public var incarnon: [IncarnonTier]?
    public var unique: [String: JSONValue]?

    public enum CodingKeys: String, CodingKey {
        case name, category, type, masteryReq, magazineSize, reloadTime, multishot, trigger
        case attacks, comb, tags, categories, compTags, incarnon, unique
        case incarnonMagazineSize = "incMagazineSize"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Weapon"
        category = try c.decodeIfPresent(String.self, forKey: .category)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        masteryReq = try c.decodeIfPresent(Int.self, forKey: .masteryReq)
        magazineSize = try c.decodeIfPresent(Double.self, forKey: .magazineSize)
        incarnonMagazineSize = try c.decodeIfPresent(Double.self, forKey: .incarnonMagazineSize)
        reloadTime = try c.decodeIfPresent(Double.self, forKey: .reloadTime)
        multishot = try c.decodeIfPresent(Double.self, forKey: .multishot)
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger)
        attacks = try c.decodeIfPresent([Attack].self, forKey: .attacks) ?? []
        comb = try c.decodeIfPresent([[Int]].self, forKey: .comb)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        categories = try c.decodeIfPresent([String].self, forKey: .categories)
        compTags = try c.decodeIfPresent([String].self, forKey: .compTags)
        if let raw = try? c.decodeIfPresent([[String: [IncarnonTier.IncarnonOption]]].self, forKey: .incarnon) {
            incarnon = raw.flatMap { dict in
                dict.compactMap { key, options in
                    guard let tier = Int(key) else { return nil }
                    return IncarnonTier(tier: tier, options: options)
                }
            }.sorted { $0.tier < $1.tier }
        } else {
            incarnon = nil
        }
        unique = try c.decodeIfPresent([String: JSONValue].self, forKey: .unique)
    }

    public init(name: String, attacks: [Attack], magazineSize: Double? = nil,
                reloadTime: Double? = nil, multishot: Double? = nil, trigger: String? = nil,
                category: String? = nil, type: String? = nil) {
        self.name = name
        self.attacks = attacks
        self.magazineSize = magazineSize
        self.reloadTime = reloadTime
        self.multishot = multishot
        self.trigger = trigger
        self.category = category
        self.type = type
    }
}

/// 灵化进化节点。
///
/// 数据里 `incarnon` 是 `[{ "18": [...], "19": [...] }, ...]` ——
/// 一个字典可以同时装多级，所以要摊平，不能只取第一个 key。
public struct IncarnonTier: Codable, Sendable, Equatable {
    public var tier: Int
    public var options: [IncarnonOption]

    public struct IncarnonOption: Codable, Sendable, Equatable {
        public var name: String
        /// 限定这条进化只作用于哪些攻击段。值形如 `Normal Attack` / `Incarnon Form`，
        /// 与武器 `attacks[].name` 同名字空间。空数组表示不限。
        public var type: [String]
        public var action: [String: JSONValue]?

        private enum CodingKeys: String, CodingKey { case name, type, action }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            type = (try? c.decodeIfPresent([String].self, forKey: .type)) ?? []
            // 数据里 `action` 有时是 `{}`、有时是 `[]`（表示没有效果），
            // 直接按字典解会让整段 incarnon 解析失败。
            action = try? c.decodeIfPresent([String: JSONValue].self, forKey: .action)
        }

        public init(name: String, type: [String] = [], action: [String: JSONValue]? = nil) {
            self.name = name
            self.type = type
            self.action = action
        }
    }

    public init(tier: Int, options: [IncarnonOption]) {
        self.tier = tier
        self.options = options
    }
}

// MARK: - 敌人

public struct Enemy: Codable, Sendable, Equatable {
    public var name: String
    public var faction: String
    public var baseLevel: Int
    public var health: Double
    public var shield: Double
    public var armor: Double
    /// 数据里只有 4 个敌人带这个字段，值是「生命的倍数」，见 README 待确认项。
    public var overguard: Double
    public var innateDR: [String: Double]
    public var elemRes: [String: Double]
    public var statusImmune: Set<String>
    public var maxProcStacks: Double?
    public var eximusDisabled: Bool

    public enum CodingKeys: String, CodingKey {
        case name, faction, health, shield, armor, overguard, innateDR, elemRes, immun, unique
        case baseLevel = "b_lvl"
        case maxProcStacks
        case eximusDisabled = "eximusOff"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Enemy"
        faction = try c.decodeIfPresent(String.self, forKey: .faction) ?? ""
        baseLevel = try c.decodeIfPresent(Int.self, forKey: .baseLevel) ?? 1
        health = try Enemy.decodeStat(c, .health)
        shield = try Enemy.decodeStat(c, .shield)
        armor = try Enemy.decodeStat(c, .armor)
        overguard = try Enemy.decodeStat(c, .overguard)
        innateDR = (try? c.decodeIfPresent([String: Double].self, forKey: .innateDR)) ?? [:]
        elemRes = (try? c.decodeIfPresent([String: Double].self, forKey: .elemRes)) ?? [:]
        let immun = (try? c.decodeIfPresent(ImmuneBlock.self, forKey: .immun))?.status ?? []
        statusImmune = Set(immun.map { $0.lowercased() })
        maxProcStacks = try c.decodeIfPresent(Double.self, forKey: .maxProcStacks)
        eximusDisabled = try c.decodeIfPresent(Bool.self, forKey: .eximusDisabled) ?? false
    }

    public init(name: String, faction: String, baseLevel: Int = 1,
                health: Double, shield: Double = 0, armor: Double = 0, overguard: Double = 0,
                innateDR: [String: Double] = [:], statusImmune: Set<String> = []) {
        self.name = name
        self.faction = faction
        self.baseLevel = baseLevel
        self.health = health
        self.shield = shield
        self.armor = armor
        self.overguard = overguard
        self.innateDR = innateDR
        self.elemRes = [:]
        self.statusImmune = statusImmune
        self.maxProcStacks = nil
        self.eximusDisabled = false
    }

    private struct StatBox: Decodable {
        let val: FlexibleNumber?
    }

    private static func decodeStat(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Double {
        guard let box = try? c.decodeIfPresent(StatBox.self, forKey: key) else { return 0 }
        return box.val?.doubleValue ?? 0
    }

    private struct ImmuneBlock: Decodable {
        let status: [String]?
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(faction, forKey: .faction)
        try c.encode(baseLevel, forKey: .baseLevel)
        try c.encode(health, forKey: .health)
        try c.encode(shield, forKey: .shield)
        try c.encode(armor, forKey: .armor)
        try c.encode(overguard, forKey: .overguard)
        try c.encode(innateDR, forKey: .innateDR)
        try c.encode(elemRes, forKey: .elemRes)
        try c.encode(maxProcStacks, forKey: .maxProcStacks)
        try c.encode(eximusDisabled, forKey: .eximusDisabled)
    }
}

// MARK: - 装配

public struct Build: Codable, Sendable, Equatable {
    /// mod 名字，必须能在 mods.json 里找到。
    public var mods: [String]
    public var riven: Riven?
    /// 灵化进化选择，格式 `"19:0"` = 第 19 级选第 0 个。
    public var incarnonPerks: [String]

    public init(mods: [String] = [], riven: Riven? = nil, incarnonPerks: [String] = []) {
        self.mods = mods
        self.riven = riven
        self.incarnonPerks = incarnonPerks
    }

    private enum CodingKeys: String, CodingKey {
        case mods, riven, incarnonPerks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? []
        riven = try c.decodeIfPresent(Riven.self, forKey: .riven)
        incarnonPerks = try c.decodeIfPresent([String].self, forKey: .incarnonPerks) ?? []
    }
}

public struct Riven: Codable, Sendable, Equatable {
    public var name: String
    public var damage: Double?
    public var multishot: Double?
    public var critChance: Double?
    public var critDamage: Double?
    public var statusChance: Double?
    public var statusDuration: Double?
    public var fireRate: Double?
    /// 对目标派系的伤害加成（Bane 类）。
    public var faction: Double?
    /// 例：`{"heat": 0.9}`。
    public var elements: [String: Double]?
    public var physical: [String: Double]?

    public init(name: String = "Riven", damage: Double? = nil, multishot: Double? = nil,
                critChance: Double? = nil, critDamage: Double? = nil, statusChance: Double? = nil,
                statusDuration: Double? = nil, fireRate: Double? = nil, faction: Double? = nil,
                elements: [String: Double]? = nil, physical: [String: Double]? = nil) {
        self.name = name
        self.damage = damage
        self.multishot = multishot
        self.critChance = critChance
        self.critDamage = critDamage
        self.statusChance = statusChance
        self.statusDuration = statusDuration
        self.fireRate = fireRate
        self.faction = faction
        self.elements = elements
        self.physical = physical
    }

    private enum CodingKeys: String, CodingKey {
        case name, damage, multishot, critChance, critDamage, statusChance
        case statusDuration, fireRate, faction, elements, physical
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Riven"
        damage = try c.decodeIfPresent(Double.self, forKey: .damage)
        multishot = try c.decodeIfPresent(Double.self, forKey: .multishot)
        critChance = try c.decodeIfPresent(Double.self, forKey: .critChance)
        critDamage = try c.decodeIfPresent(Double.self, forKey: .critDamage)
        statusChance = try c.decodeIfPresent(Double.self, forKey: .statusChance)
        statusDuration = try c.decodeIfPresent(Double.self, forKey: .statusDuration)
        fireRate = try c.decodeIfPresent(Double.self, forKey: .fireRate)
        faction = try c.decodeIfPresent(Double.self, forKey: .faction)
        elements = try c.decodeIfPresent([String: Double].self, forKey: .elements)
        physical = try c.decodeIfPresent([String: Double].self, forKey: .physical)
    }
}

public struct WarframeBuffs: Codable, Sendable, Equatable {
    /// 加法总伤害（Serration 同一乘区之外的部分，例如 Vex Armor）。
    public var damageBonus: Double
    /// 相对暴击几率加成，叠加到 mod 的 relative bonus 上。
    public var critChanceBonus: Double
    /// 暴伤绝对加成。
    public var critDamageBonus: Double
    public var multishotBonus: Double
    public var fireRateBonus: Double
    /// 状态伤害加成（Rifle Elementalist 那类），与其它 status damage 加算。
    public var statusDamageBonus: Double
    /// 派系伤害加成（Roar / Bane），对 DOT 二次结算。
    public var factionBonus: Double

    public init(damageBonus: Double = 0, critChanceBonus: Double = 0, critDamageBonus: Double = 0,
                multishotBonus: Double = 0, fireRateBonus: Double = 0,
                statusDamageBonus: Double = 0, factionBonus: Double = 0) {
        self.damageBonus = damageBonus
        self.critChanceBonus = critChanceBonus
        self.critDamageBonus = critDamageBonus
        self.multishotBonus = multishotBonus
        self.fireRateBonus = fireRateBonus
        self.statusDamageBonus = statusDamageBonus
        self.factionBonus = factionBonus
    }

    private enum CodingKeys: String, CodingKey {
        case damageBonus, critChanceBonus, critDamageBonus, multishotBonus
        case fireRateBonus, statusDamageBonus, factionBonus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damageBonus = try c.decodeIfPresent(Double.self, forKey: .damageBonus) ?? 0
        critChanceBonus = try c.decodeIfPresent(Double.self, forKey: .critChanceBonus) ?? 0
        critDamageBonus = try c.decodeIfPresent(Double.self, forKey: .critDamageBonus) ?? 0
        multishotBonus = try c.decodeIfPresent(Double.self, forKey: .multishotBonus) ?? 0
        fireRateBonus = try c.decodeIfPresent(Double.self, forKey: .fireRateBonus) ?? 0
        statusDamageBonus = try c.decodeIfPresent(Double.self, forKey: .statusDamageBonus) ?? 0
        factionBonus = try c.decodeIfPresent(Double.self, forKey: .factionBonus) ?? 0
    }

    public static let none = WarframeBuffs()
}

// MARK: - 选项

public struct Options: Codable, Sendable, Equatable {
    /// 时间窗口（秒），1–60。
    public var window: Double
    public var steelPath: Bool
    public var eximus: Bool
    /// 小队人数，影响少数按队伍人数缩放的敌人 / mod。
    public var squadSize: Int
    /// 外部削甲比例 0–1（战甲技能、其他来源）。
    public var armorStrip: Double
    /// 开打前已有的病毒层数 0–10。
    public var externalViralStacks: Double
    public var headshot: Bool
    public var headshotMultiplier: Double
    /// 到目标的距离；nil 表示不受伤害衰减影响。
    public var distance: Double?
    /// 是否在弱点（Primary Acuity 这类条件 mod 需要）。
    public var weakPoint: Bool
    public var warframe: WarframeBuffs

    public init(window: Double = 20, steelPath: Bool = false, eximus: Bool = false,
                squadSize: Int = 1, armorStrip: Double = 0, externalViralStacks: Double = 0,
                headshot: Bool = false, headshotMultiplier: Double = Rules.defaultHeadshotMultiplier,
                distance: Double? = nil, weakPoint: Bool = false,
                warframe: WarframeBuffs = .none) {
        self.window = window
        self.steelPath = steelPath
        self.eximus = eximus
        self.squadSize = squadSize
        self.armorStrip = armorStrip
        self.externalViralStacks = externalViralStacks
        self.headshot = headshot
        self.headshotMultiplier = headshotMultiplier
        self.distance = distance
        self.weakPoint = weakPoint
        self.warframe = warframe
    }

    private enum CodingKeys: String, CodingKey {
        case window, steelPath, eximus, squadSize, armorStrip, externalViralStacks
        case headshot, headshotMultiplier, distance, weakPoint, warframe
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Options()
        window = try c.decodeIfPresent(Double.self, forKey: .window) ?? defaults.window
        steelPath = try c.decodeIfPresent(Bool.self, forKey: .steelPath) ?? false
        eximus = try c.decodeIfPresent(Bool.self, forKey: .eximus) ?? false
        squadSize = try c.decodeIfPresent(Int.self, forKey: .squadSize) ?? 1
        armorStrip = try c.decodeIfPresent(Double.self, forKey: .armorStrip) ?? 0
        externalViralStacks = try c.decodeIfPresent(Double.self, forKey: .externalViralStacks) ?? 0
        headshot = try c.decodeIfPresent(Bool.self, forKey: .headshot) ?? false
        headshotMultiplier = try c.decodeIfPresent(Double.self, forKey: .headshotMultiplier)
            ?? Rules.defaultHeadshotMultiplier
        distance = try c.decodeIfPresent(Double.self, forKey: .distance)
        weakPoint = try c.decodeIfPresent(Bool.self, forKey: .weakPoint) ?? false
        warframe = try c.decodeIfPresent(WarframeBuffs.self, forKey: .warframe) ?? .none
    }
}

// MARK: - 结果

public enum Layer: String, Codable, CaseIterable, Sendable {
    case health
    case armor
    case shield
    case overguard

    public var zhName: String {
        switch self {
        case .health: return "生命"
        case .armor: return "护甲"
        case .shield: return "护盾"
        case .overguard: return "超宏"
        }
    }
}

public struct LayerResult: Codable, Sendable, Equatable {
    public var layer: Layer
    public var maxHP: Double
    public var damage: Double
    public var dps: Double
    /// 该层各伤害类型**扣完减伤之后**的实际伤害。
    ///
    /// 伤害向量全程按类型保留，只在写结果时才求和；所以免疫某一类型时，
    /// 该类型在这里是 0，其余类型不受影响。
    public var byType: [String: Double]
    /// 累计伤害第一次达到该层血量的时刻；窗口内没打死就是 nil。
    public var ttk: Double?
}

public struct AttackResult: Codable, Sendable, Equatable {
    public var attack: String
    public var shots: Double
    public var dps: Double
    public var directDamage: Double
    public var dotDamage: Double
    /// 命中直伤 + DOT 的未减免伤害，按类型分解（扣减伤之前）。
    public var rawByType: [String: Double]
    public var layers: [LayerResult]
    /// 各状态的期望触发次数。
    public var procs: [String: Double]
    public var notes: [String]
}

public struct EnemyStats: Codable, Sendable, Equatable {
    public var health: Double
    public var armor: Double
    public var shield: Double
    public var overguard: Double
    public var armorDR: Double
}

public struct Result: Codable, Sendable, Equatable {
    public var weapon: String
    public var enemy: String
    public var level: Int
    public var window: Double
    public var enemyStats: EnemyStats
    public var attacks: [AttackResult]
    public var notes: [String]
}

public struct DamageInput: Codable, Sendable {
    public var weapon: Weapon
    public var enemy: Enemy
    public var level: Int
    public var build: Build
    public var options: Options

    public init(weapon: Weapon, enemy: Enemy, level: Int, build: Build = Build(), options: Options = Options()) {
        self.weapon = weapon
        self.enemy = enemy
        self.level = level
        self.build = build
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case weapon, enemy, level, build, options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weapon = try c.decode(Weapon.self, forKey: .weapon)
        enemy = try c.decode(Enemy.self, forKey: .enemy)
        level = try c.decode(Int.self, forKey: .level)
        build = try c.decodeIfPresent(Build.self, forKey: .build) ?? Build()
        options = try c.decodeIfPresent(Options.self, forKey: .options) ?? Options()
    }
}

// MARK: - JSON 小工具

/// 数字可能是 `1000` 也可能是 `"1000"`，统一吃下来。
public enum FlexibleNumber: Codable, Sendable, Equatable {
    case number(Double)
    case text(String)

    public var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .text(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        }
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let d = try? single.decode(Double.self) { self = .number(d); return }
        if let s = try? single.decode(String.self) { self = .text(s); return }
        throw DecodingError.typeMismatch(FlexibleNumber.self,
                                         .init(codingPath: decoder.codingPath,
                                               debugDescription: "not a number or string"))
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .number(let d): try single.encode(d)
        case .text(let s): try single.encode(s)
        }
    }
}

/// 只用来把不认识的 JSON 原样装下的容器。
public enum JSONValue: Codable, Sendable, Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let d = try? single.decode(Double.self) { self = .number(d); return }
        if let s = try? single.decode(String.self) { self = .string(s); return }
        if let b = try? single.decode(Bool.self) { self = .bool(b); return }
        if let arr = try? single.decode([JSONValue].self) { self = .array(arr); return }
        if let dict = try? single.decode([String: JSONValue].self) { self = .object(dict); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .number(let d): try single.encode(d)
        case .string(let s): try single.encode(s)
        case .bool(let b): try single.encode(b)
        case .array(let a): try single.encode(a)
        case .object(let o): try single.encode(o)
        case .null: try single.encodeNil()
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = Int(stringValue) }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}
