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
    /// 原始武器数据的攻击类别（例如 `h`、`s`、`hs`）。它和武器的
    /// `type` 不同，用来判断该攻击是否属于架势普通连段。
    public var attackType: String?
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
    /// 原始攻击数据的 `isHeavy` 标记。它和 UI 的“将普通攻击按重击计算”开关
    /// 一起决定是否使用默认重击连段。
    public var isHeavy: Bool
    /// 网站武器数据中的 `sniperCombo` 标记。它不是“武器分类是狙击枪”这一
    /// 粗略判断：只有带此标记的攻击段才读取狙击连击倍率（关闭时仍使用网站
    /// 的固有 1.5x）。
    public var sniperCombo: Bool
    /// 数据字段 `isCoMult`：Condition Overload / Galvanized Shot 一类的
    /// 每状态伤害是否与基础伤害池相乘，而不是通常的加法叠加。
    public var conditionalDamageIsMultiplicative: Bool
    public var radius: Double?
    /// 强制触发的状态类型。站点数据既有顶层 `force_procs`，也有
    /// `unique.force_procs`；两种形式都是字符串数组。
    ///
    /// 保留原始字符串而不是在解码时丢弃未知值，让模拟器能够给出诊断。
    public var forceProcs: [String]?
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
        attackType: String? = nil,
        shotType: String? = nil,
        noHeadshotMultiplier: Bool = false,
        multishot: Double? = nil,
        burstCount: Int? = nil,
        burstDelay: Double? = nil,
        chargeTime: Double? = nil,
        falloff: Falloff? = nil,
        isIncarnonForm: Bool = false,
        isBeam: Bool = false,
        isHeavy: Bool = false,
        sniperCombo: Bool = false,
        conditionalDamageIsMultiplicative: Bool = false,
        radius: Double? = nil,
        forceProcs: [String]? = nil,
        unique: [String: JSONValue]? = nil
    ) {
        self.name = name
        self.speed = speed
        self.critChance = critChance
        self.critMultiplier = critMultiplier
        self.statusChance = statusChance
        self.damage = damage
        self.attackType = attackType
        self.shotType = shotType
        self.noHeadshotMultiplier = noHeadshotMultiplier
        self.multishot = multishot
        self.burstCount = burstCount
        self.burstDelay = burstDelay
        self.chargeTime = chargeTime
        self.falloff = falloff
        self.isIncarnonForm = isIncarnonForm
        self.isBeam = isBeam
        self.isHeavy = isHeavy
        self.sniperCombo = sniperCombo
        self.conditionalDamageIsMultiplicative = conditionalDamageIsMultiplicative
        self.radius = radius
        self.forceProcs = forceProcs
        self.unique = unique
    }

    private enum CodingKeys: String, CodingKey {
        case name, speed, damage, multishot, radius, unique, falloff
        case attackType = "type"
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
        case isHeavy
        case sniperCombo
        case conditionalDamageIsMultiplicative = "isCoMult"
        case forceProcs = "force_procs"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Attack"
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        critChance = try c.decodeIfPresent(Double.self, forKey: .critChance) ?? 0
        critMultiplier = try c.decodeIfPresent(Double.self, forKey: .critMultiplier) ?? 1
        statusChance = try c.decodeIfPresent(Double.self, forKey: .statusChance) ?? 0
        attackType = try c.decodeIfPresent(String.self, forKey: .attackType)
        shotType = try c.decodeIfPresent(String.self, forKey: .shotType)
        noHeadshotMultiplier = try c.decodeIfPresent(Bool.self, forKey: .noHeadshotMultiplier) ?? false
        multishot = try c.decodeIfPresent(Double.self, forKey: .multishot)
        burstCount = try c.decodeIfPresent(Int.self, forKey: .burstCount)
        burstDelay = try c.decodeIfPresent(Double.self, forKey: .burstDelay)
        chargeTime = try c.decodeIfPresent(Double.self, forKey: .chargeTime)
        falloff = try c.decodeIfPresent(Falloff.self, forKey: .falloff)
        isIncarnonForm = (try c.decodeIfPresent(Int.self, forKey: .isIncarnonForm) ?? 0) != 0
        isBeam = try c.decodeIfPresent(Bool.self, forKey: .isBeam) ?? false
        isHeavy = try c.decodeIfPresent(Bool.self, forKey: .isHeavy) ?? false
        sniperCombo = try c.decodeIfPresent(Bool.self, forKey: .sniperCombo) ?? false
        conditionalDamageIsMultiplicative = try c.decodeIfPresent(Bool.self, forKey: .conditionalDamageIsMultiplicative) ?? false
        radius = try c.decodeIfPresent(Double.self, forKey: .radius)
        unique = try c.decodeIfPresent([String: JSONValue].self, forKey: .unique)
        forceProcs = Attack.decodeForceProcs(from: c, unique: unique)
        damage = try Attack.decodeDamage(from: c)
    }

    private static func decodeForceProcs(
        from c: KeyedDecodingContainer<CodingKeys>,
        unique: [String: JSONValue]?
    ) -> [String]? {
        // 少数武器把它放在攻击段顶层；不能让数组与旧的错误字典类型相撞后
        // 令整把武器解码失败。
        if let direct = try? c.decode([String].self, forKey: .forceProcs) {
            return direct
        }
        if let direct = try? c.decode(String.self, forKey: .forceProcs) {
            return [direct]
        }

        // 大多数数据使用 `unique: { "force_procs": [ ... ] }`。
        guard let raw = unique?["force_procs"] else { return nil }
        if let values = raw.arrayValue {
            return values.compactMap(\.stringValue)
        }
        if let value = raw.stringValue { return [value] }
        return nil
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
    /// Weapon-level heavy-attack wind-up time.  It is added to a heavy combo
    /// cycle, never to normal stance contact timing.
    public var windUp: Double?
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
    /// The website data uses this source-owned discriminator for the small
    /// number of weapons whose ability strength enters their damage contract.
    /// It is deliberately raw data here; BuildResolver decides whether and
    /// where a particular value changes a resolved attack.
    public var strengthType: String?
    /// A source-owned final outgoing multiplier (currently used by weapons
    /// such as Regulators).  Keeping it in the decoded weapon prevents a UI
    /// or a weapon-name table from having to recreate the data rule.
    public var additionalBuff: Double?

    public enum CodingKeys: String, CodingKey {
        case name, category, type, masteryReq, magazineSize, reloadTime, windUp, multishot, trigger
        case attacks, comb, tags, categories, compTags, incarnon, unique, strengthType, additionalBuff
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
        windUp = try c.decodeIfPresent(Double.self, forKey: .windUp)
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
        strengthType = try c.decodeIfPresent(String.self, forKey: .strengthType)
        additionalBuff = try c.decodeIfPresent(Double.self, forKey: .additionalBuff)
    }

    public init(name: String, attacks: [Attack], magazineSize: Double? = nil,
                reloadTime: Double? = nil, windUp: Double? = nil,
                multishot: Double? = nil, trigger: String? = nil,
                category: String? = nil, type: String? = nil) {
        self.name = name
        self.attacks = attacks
        self.magazineSize = magazineSize
        self.reloadTime = reloadTime
        self.windUp = windUp
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
    /// 数据内显式的 Overguard 基值；若不存在，Eximus 使用通用基值 12。
    public var overguard: Double
    public var innateDR: [String: Double]
    public var elemRes: [String: Double]
    public var statusImmune: Set<String>
    public var maxProcStacks: Double?
    public var eximusDisabled: Bool
    /// 站点敌人数据的 `showPartyCount`。仅该字段为 true 的目标才会显示并使用
    /// 小队人数生命倍率；普通敌人不能被这个通用 UI 选项意外放大生命。
    public var showPartyCount: Bool

    public enum CodingKeys: String, CodingKey {
        case name, faction, health, shield, armor, overguard, innateDR, elemRes, immun, unique, showPartyCount
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
        showPartyCount = try c.decodeIfPresent(Bool.self, forKey: .showPartyCount) ?? false
    }

    public init(name: String, faction: String, baseLevel: Int = 1,
                health: Double, shield: Double = 0, armor: Double = 0, overguard: Double = 0,
                innateDR: [String: Double] = [:], statusImmune: Set<String> = [],
                showPartyCount: Bool = false) {
        self.name = name
        self.faction = faction
        self.baseLevel = baseLevel
        self.health = health
        self.shield = shield
        self.armor = armor
        self.overguard = overguard
        self.innateDR = innateDR
        self.elemRes = [:]
        self.statusImmune = Set(statusImmune.map { $0.lowercased() })
        self.maxProcStacks = nil
        self.eximusDisabled = false
        self.showPartyCount = showPartyCount
    }

    private struct StatBox: Codable {
        let val: FlexibleNumber?
    }

    private static func decodeStat(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Double {
        // 站点数据是 `{ "val": 100 }`，而公开 DamageRequest/Enemy 编码使用
        // 直接数字。两种合法表示必须得到同一数值，不能在不报错的情况下归零。
        if let direct = try? c.decode(FlexibleNumber.self, forKey: key) {
            return direct.doubleValue ?? 0
        }
        if let box = try? c.decode(StatBox.self, forKey: key) {
            return box.val?.doubleValue ?? 0
        }
        return 0
    }

    private struct ImmuneBlock: Codable {
        let status: [String]?

        init(status: [String]?) {
            self.status = status
        }
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
        if !statusImmune.isEmpty {
            try c.encode(ImmuneBlock(status: statusImmune.sorted()), forKey: .immun)
        }
        try c.encode(maxProcStacks, forKey: .maxProcStacks)
        try c.encode(eximusDisabled, forKey: .eximusDisabled)
        try c.encode(showPartyCount, forKey: .showPartyCount)
    }
}

// MARK: - 装配

/// 武器界面中一张卡实际所在的位置。元素合成依赖位置顺序，所以不能只保存
/// 一组无序的 Mod 名称。
public struct SlottedMod: Codable, Sendable, Equatable, Hashable {
    public var slot: Int
    public var name: String
    /// An inventory import may provide a source-proven multiplier for a
    /// non-max-rank card. `nil` means the ordinary data-table value is already
    /// the exact equipped value (normally a max-rank card). This is deliberately
    /// a scalar only for cards whose whole source action was verified to scale
    /// proportionally; callers must not use it as a guess for arbitrary ranks.
    public var actionScale: Double?
    /// A source-proven ratio for a *single* condition input on this concrete
    /// card.  It is intentionally separate from `actionScale`: a ranked
    /// stacking effect can have a smaller value per ability cast while keeping
    /// the same final cap.  For example, rank-4 Melee Exposure gains 50%
    /// Corrosive per cast but still caps at 240%, so treating its complete
    /// action as 5/6 of the full card would incorrectly reduce that cap.
    ///
    /// `nil` means one in-game input has the source table's ordinary full-rank
    /// value.  The import layer may set this only after it has read and
    /// cross-checked the exact equipped rank's source text.
    public var conditionalStepScale: Double?

    public init(slot: Int, name: String, actionScale: Double? = nil,
                conditionalStepScale: Double? = nil) {
        self.slot = slot
        self.name = name
        self.actionScale = actionScale
        self.conditionalStepScale = conditionalStepScale
    }
}

public struct Build: Codable, Sendable, Equatable {
    /// mod 名字，必须能在 mods.json 里找到。
    ///
    /// 这是旧输入格式，列表顺序仍会被保留。新输入应优先用 slottedMods，
    /// 因为它能表达 Exilus、Arcane 与元素 Mod 的真实位置。
    public var mods: [String]
    /// 带槽位的 Mod 输入。非空时，它是本次计算的武器 Mod 来源，mods 只为
    /// 兼容旧存档保留。
    public var slottedMods: [SlottedMod]
    public var riven: Riven?
    /// 紫卡占用的普通 Mod 槽。nil 保持旧 API 的“在普通 Mod 后处理”语义；
    /// 原生界面和对拍 fixture 必须显式给出该值，避免元素顺序被猜测。
    public var rivenSlot: Int?
    /// 赤毒 / 信条武器实例的继承元素伤害比例，例如 `{"toxin": 0.6}`。
    /// 这是武器实例固有属性，不是槽位元素 Mod，也不是外部附伤。
    public var progenitorElements: [String: Double]
    /// 灵化进化选择，格式 `"19:0"` = 第 19 级选第 0 个。
    public var incarnonPerks: [String]
    /// 已装备架势 Mod 中选中的普通连段名称。架势卡本身仍由 `slottedMods`
    /// 的第 9 槽表达；这里仅记录用户在该卡的连段下拉框中选了哪一项。
    public var stanceCombo: String?

    public init(mods: [String] = [], slottedMods: [SlottedMod] = [],
                riven: Riven? = nil, rivenSlot: Int? = nil,
                progenitorElements: [String: Double] = [:],
                incarnonPerks: [String] = [], stanceCombo: String? = nil) {
        self.mods = mods
        self.slottedMods = slottedMods
        self.riven = riven
        self.rivenSlot = rivenSlot
        self.progenitorElements = progenitorElements
        self.incarnonPerks = incarnonPerks
        self.stanceCombo = stanceCombo
    }

    private enum CodingKeys: String, CodingKey {
        case mods, slottedMods, riven, rivenSlot, progenitorElements, incarnonPerks, stanceCombo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? []
        slottedMods = try c.decodeIfPresent([SlottedMod].self, forKey: .slottedMods) ?? []
        riven = try c.decodeIfPresent(Riven.self, forKey: .riven)
        rivenSlot = try c.decodeIfPresent(Int.self, forKey: .rivenSlot)
        progenitorElements = try c.decodeIfPresent([String: Double].self,
                                                    forKey: .progenitorElements) ?? [:]
        incarnonPerks = try c.decodeIfPresent([String].self, forKey: .incarnonPerks) ?? []
        stanceCombo = try c.decodeIfPresent(String.self, forKey: .stanceCombo)
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
    /// 装填速度相对加成；正值使换弹时间除以 `1 + value`。
    public var reloadSpeed: Double?
    /// 对目标派系的伤害加成（Bane 类）。
    public var faction: Double?
    /// 按派系区分的紫卡 Bane 词条；键接受 `Grineer`、`Corpus`、`Infested`、`Orokin`。
    public var factionBonuses: [String: Double]?
    /// 例：`{"heat": 0.9}`。
    public var elements: [String: Double]?
    public var physical: [String: Double]?

    public init(name: String = "Riven", damage: Double? = nil, multishot: Double? = nil,
                critChance: Double? = nil, critDamage: Double? = nil, statusChance: Double? = nil,
                statusDuration: Double? = nil, fireRate: Double? = nil, reloadSpeed: Double? = nil,
                faction: Double? = nil,
                factionBonuses: [String: Double]? = nil,
                elements: [String: Double]? = nil, physical: [String: Double]? = nil) {
        self.name = name
        self.damage = damage
        self.multishot = multishot
        self.critChance = critChance
        self.critDamage = critDamage
        self.statusChance = statusChance
        self.statusDuration = statusDuration
        self.fireRate = fireRate
        self.reloadSpeed = reloadSpeed
        self.faction = faction
        self.factionBonuses = factionBonuses
        self.elements = elements
        self.physical = physical
    }

    private enum CodingKeys: String, CodingKey {
        case name, damage, multishot, critChance, critDamage, statusChance
        case statusDuration, fireRate, reloadSpeed, faction, factionBonuses, elements, physical
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
        reloadSpeed = try c.decodeIfPresent(Double.self, forKey: .reloadSpeed)
        faction = try c.decodeIfPresent(Double.self, forKey: .faction)
        factionBonuses = try c.decodeIfPresent([String: Double].self, forKey: .factionBonuses)
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

/// 一个外部来源已经换算好的武器修正。
///
/// 它不把名字当作公式：`name` 只用于结果追踪；数值字段才是实际输入。
/// `elements` 中的值是相对于武器原始基础伤害的额外直击元素伤害，且在
/// 武器自身的元素合并之后加入（适用于 Shock Trooper、Venom Dose、Nourish
/// 一类外部附伤，而不是武器槽位元素 Mod）。
public struct ExternalWeaponBuff: Codable, Sendable, Equatable {
    public var damageBonus: Double
    public var critChanceBonus: Double
    public var critDamageBonus: Double
    public var multishotBonus: Double
    public var fireRateBonus: Double
    public var reloadSpeedBonus: Double
    public var statusChanceBonus: Double
    public var statusDurationBonus: Double
    public var statusDamageBonus: Double
    public var factionBonus: Double
    public var elements: [String: Double]
    /// 对同类伤害型状态的元素伤害加成；与 `elements` 分开，避免把“附加一段
    /// 伤害”误写成“增加该状态 DOT”。
    public var statusElementBonuses: [String: Double]

    public init(damageBonus: Double = 0, critChanceBonus: Double = 0,
                critDamageBonus: Double = 0, multishotBonus: Double = 0,
                fireRateBonus: Double = 0, reloadSpeedBonus: Double = 0,
                statusChanceBonus: Double = 0, statusDurationBonus: Double = 0,
                statusDamageBonus: Double = 0, factionBonus: Double = 0,
                elements: [String: Double] = [:],
                statusElementBonuses: [String: Double] = [:]) {
        self.damageBonus = damageBonus
        self.critChanceBonus = critChanceBonus
        self.critDamageBonus = critDamageBonus
        self.multishotBonus = multishotBonus
        self.fireRateBonus = fireRateBonus
        self.reloadSpeedBonus = reloadSpeedBonus
        self.statusChanceBonus = statusChanceBonus
        self.statusDurationBonus = statusDurationBonus
        self.statusDamageBonus = statusDamageBonus
        self.factionBonus = factionBonus
        self.elements = elements
        self.statusElementBonuses = statusElementBonuses
    }

    private enum CodingKeys: String, CodingKey {
        case damageBonus, critChanceBonus, critDamageBonus, multishotBonus
        case fireRateBonus, reloadSpeedBonus, statusChanceBonus, statusDurationBonus
        case statusDamageBonus, factionBonus, elements, statusElementBonuses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        damageBonus = try c.decodeIfPresent(Double.self, forKey: .damageBonus) ?? 0
        critChanceBonus = try c.decodeIfPresent(Double.self, forKey: .critChanceBonus) ?? 0
        critDamageBonus = try c.decodeIfPresent(Double.self, forKey: .critDamageBonus) ?? 0
        multishotBonus = try c.decodeIfPresent(Double.self, forKey: .multishotBonus) ?? 0
        fireRateBonus = try c.decodeIfPresent(Double.self, forKey: .fireRateBonus) ?? 0
        reloadSpeedBonus = try c.decodeIfPresent(Double.self, forKey: .reloadSpeedBonus) ?? 0
        statusChanceBonus = try c.decodeIfPresent(Double.self, forKey: .statusChanceBonus) ?? 0
        statusDurationBonus = try c.decodeIfPresent(Double.self, forKey: .statusDurationBonus) ?? 0
        statusDamageBonus = try c.decodeIfPresent(Double.self, forKey: .statusDamageBonus) ?? 0
        factionBonus = try c.decodeIfPresent(Double.self, forKey: .factionBonus) ?? 0
        elements = try c.decodeIfPresent([String: Double].self, forKey: .elements) ?? [:]
        statusElementBonuses = try c.decodeIfPresent([String: Double].self,
                                                      forKey: .statusElementBonuses) ?? [:]
    }

    public static let none = ExternalWeaponBuff()
}

/// 一个来自战甲、同伴或任意环境的来源。
///
/// `mod` 非空时精确查询本地 ModLibrary；不会根据 `name` 猜测效果。`conditionValue`
/// 是该来源在这次射击开始时已经满足的条件值（例如 1 = 单条件已生效、12 = 12x
/// 连击），不提供时所有 `WITH_COND` 效果均为零。`buff` 可与 `mod` 叠加，用于
/// 没有数据表条目的技能、光环或队友增益。
public struct ExternalEffectSource: Codable, Sendable, Equatable {
    public var name: String
    public var mod: String?
    public var active: Bool
    public var conditionValue: Double?
    /// Optional source-specific Ability Strength.  `nil` means this source
    /// uses `Options.abilityStrength`; a source-bound client can instead pass
    /// the strength resolved from that caster's actual A/B/C configuration.
    public var abilityStrength: Double?
    /// Optional coefficient of the equipped external Mod's own rank.  Damage
    /// data stores some augments at their max-rank action (1.0), while an
    /// account configuration can equip a lower rank.  This scales only the
    /// strength-routed action for that source; it is not a second ability-
    /// strength input.
    public var effectScale: Double?
    public var buff: ExternalWeaponBuff

    public init(name: String, mod: String? = nil, active: Bool = true,
                conditionValue: Double? = nil, abilityStrength: Double? = nil,
                effectScale: Double? = nil,
                buff: ExternalWeaponBuff = .none) {
        self.name = name
        self.mod = mod
        self.active = active
        self.conditionValue = conditionValue
        self.abilityStrength = abilityStrength
        self.effectScale = effectScale
        self.buff = buff
    }

    private enum CodingKeys: String, CodingKey {
        case name, mod, active, conditionValue, abilityStrength, effectScale, buff
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "External effect"
        mod = try c.decodeIfPresent(String.self, forKey: .mod)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        conditionValue = try c.decodeIfPresent(Double.self, forKey: .conditionValue)
        abilityStrength = try c.decodeIfPresent(Double.self, forKey: .abilityStrength)
        effectScale = try c.decodeIfPresent(Double.self, forKey: .effectScale)
        buff = try c.decodeIfPresent(ExternalWeaponBuff.self, forKey: .buff) ?? .none
    }
}

/// 开火时已在目标身上的一种状态。外部来源并不等同于这把武器造成的 DOT：
/// 因此它提供状态层数、剩余时间和 Heat 护甲剥离进度，但不会伪造未知的 DOT seed。
public struct InitialStatusEffect: Codable, Sendable, Equatable {
    /// Damage/status 名称，例如 `viral`、`corrosive`、`heat`、`puncture`。
    public var type: String
    public var stacks: Double
    /// 从 t=0 起仍会持续的秒数；默认游戏基础状态时长 6 秒。
    public var remainingDuration: Double
    /// 仅 Heat 使用：该 Heat 护甲剥离已经走过的秒数，默认 0。
    public var heatArmorElapsed: Double

    public init(type: String, stacks: Double = 1,
                remainingDuration: Double = Rules.statusBaseDuration,
                heatArmorElapsed: Double = 0) {
        self.type = type
        self.stacks = stacks
        self.remainingDuration = remainingDuration
        self.heatArmorElapsed = heatArmorElapsed
    }

    private enum CodingKeys: String, CodingKey {
        case type, stacks, remainingDuration, heatArmorElapsed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        stacks = try c.decodeIfPresent(Double.self, forKey: .stacks) ?? 1
        remainingDuration = try c.decodeIfPresent(Double.self, forKey: .remainingDuration)
            ?? Rules.statusBaseDuration
        heatArmorElapsed = try c.decodeIfPresent(Double.self, forKey: .heatArmorElapsed) ?? 0
    }
}

/// 外部环境的来源分组。分组只用于输入/UI 与结果追踪；三个分组的公式地位相同。
public struct EnvironmentEffects: Codable, Sendable, Equatable {
    public var warframeMods: [ExternalEffectSource]
    public var companionMods: [ExternalEffectSource]
    public var buffs: [ExternalEffectSource]
    /// 开火前已经在敌人身上的完整状态，带有限时和 Heat 的剥甲进度。
    public var initialStatuses: [InitialStatusEffect]
    /// `initialStatuses` 的简写。键接受 damage/status 名称，例如 `viral`、
    /// `corrosive`、`heat`；默认只在开火后的 6 秒内存在。
    public var initialStatusStacks: [String: Double]

    public init(warframeMods: [ExternalEffectSource] = [],
                companionMods: [ExternalEffectSource] = [],
                buffs: [ExternalEffectSource] = [],
                initialStatuses: [InitialStatusEffect] = [],
                initialStatusStacks: [String: Double] = [:]) {
        self.warframeMods = warframeMods
        self.companionMods = companionMods
        self.buffs = buffs
        self.initialStatuses = initialStatuses
        self.initialStatusStacks = initialStatusStacks
    }

    private enum CodingKeys: String, CodingKey {
        case warframeMods, companionMods, buffs, initialStatuses, initialStatusStacks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        warframeMods = try c.decodeIfPresent([ExternalEffectSource].self, forKey: .warframeMods) ?? []
        companionMods = try c.decodeIfPresent([ExternalEffectSource].self, forKey: .companionMods) ?? []
        buffs = try c.decodeIfPresent([ExternalEffectSource].self, forKey: .buffs) ?? []
        initialStatuses = try c.decodeIfPresent([InitialStatusEffect].self, forKey: .initialStatuses) ?? []
        initialStatusStacks = try c.decodeIfPresent([String: Double].self,
                                                     forKey: .initialStatusStacks) ?? [:]
    }

    public var allSources: [ExternalEffectSource] { warframeMods + companionMods + buffs }

    public func initialStatusStackCount(named name: String) -> Double {
        let shorthand = initialStatusStacks.first {
            $0.key.compare(name, options: [.caseInsensitive]) == .orderedSame
        }?.value ?? 0
        let detailed = initialStatuses.reduce(0.0) { partial, status in
            partial + (status.type.compare(name, options: [.caseInsensitive]) == .orderedSame
                       ? status.stacks : 0)
        }
        return shorthand + detailed
    }

    public static let none = EnvironmentEffects()
}

// MARK: - 选项

/// warframe-damage 的“自定义属性”面板所使用的稳定键。
///
/// 这些键只描述输入的种类与显示单位；结算顺序由 `BuildResolver` / `WeaponSimulator`
/// 决定，界面不根据字符串名称自行套公式。`Options.customStats` 保存的数值和网站
/// 内部 `customStats` 相同：`usesPercentInput == true` 的项目在 UI 上填写百分数、
/// 存入时已除以 100；其余项目保留网站所用的原始数值。
public enum CustomStatKey: String, CaseIterable, Codable, Sendable {
    case base
    case basePerStatus = "base_per_status"
    case flatChangeDamage = "flat_change_dmg"
    case abilityCombo
    case critChance = "crit_chance"
    case multiplicativeCritChance = "mult_crit_chance"
    case flatCritChance = "flat_crit_chance"
    case weakPointCritChance = "crit_chance_weakp"
    case critMultiplier = "crit_mult"
    case flatCritMultiplier = "crit_mult_add"
    case finalCritMultiplier = "crit_mult_mult"
    case statusChance = "status_chance"
    case statusChanceMultiplier = "status_chance_mult"
    case absoluteStatusChance = "absolute_status_chance"
    case statusDamage = "status_damage"
    case vulnerableStatusDamage = "vuln_status_damage"
    case speed
    case multishot
    case magazineSize
    case reloadTime
    case headshotDamage = "mult_for_head"
    case weakPointDamage = "headshot_mult"
    case initialCombo
    case damageVulnerability = "dmgVulnerability"
    case heatInherit
    case heatAdd

    /// 网站的 `data-d="1"` 字段：UI 显示百分数，计算输入保存为比率。
    public var usesPercentInput: Bool {
        switch self {
        case .base, .basePerStatus, .critChance, .multiplicativeCritChance,
             .flatCritChance, .weakPointCritChance, .critMultiplier,
             .statusChance, .statusChanceMultiplier, .statusDamage,
             .vulnerableStatusDamage, .speed, .magazineSize, .reloadTime,
             .headshotDamage, .weakPointDamage, .damageVulnerability,
             .heatInherit, .heatAdd:
            return true
        case .flatChangeDamage, .abilityCombo, .flatCritMultiplier,
             .finalCritMultiplier, .absoluteStatusChance, .multishot,
             .initialCombo:
            return false
        }
    }

    /// Converts the number shown in the website-compatible input control to
    /// the stable `Options.customStats` unit.  This is deliberately an input
    /// contract, not a damage calculation: `BuildResolver` remains the only
    /// owner of the stat's formula and application order.
    public func inputValue(fromDisplayValue value: Double) -> Double {
        usesPercentInput ? value / 100 : value
    }
}

/// Stable identifiers for named environment effects whose formula position has
/// been implemented and tested in the core. The name is an input key only;
/// `BuildResolver` owns the corresponding damage-pool operation.
public enum ScenarioEffectID: String, CaseIterable, Codable, Sendable, Hashable {
    case roar
    case eclipse
    case nourish
    /// Xata's Whisper is an independently routed Void-damage instance.  It is
    /// intentionally not represented as an ordinary elemental Mod because its
    /// faction and defense stages differ from the weapon's own damage vector.
    case xata
    /// Toxic Lash adds a distinct Toxin direct hit and fixed-duration Toxin
    /// ticks.  It has its own melee coefficient and cannot be represented by a
    /// weapon-slot elemental Mod.
    case toxicLash
    case flatCriticalChance
    /// The website exposes Madurai as a checkbox, not a user-entered percent.
    /// Its enabled value is resolved by the core, not by a SwiftUI view.
    case madurai

    /// The presentation contract for this site-named option.  This is kept in
    /// DamageKit rather than in a SwiftUI screen so every client sends the
    /// same input units and defaults.  It deliberately describes input only;
    /// `BuildResolver` remains the only place that decides a damage-pool
    /// operation.
    public var inputContract: ScenarioEffectInputContract {
        switch self {
        case .roar:
            return .percentage(defaultDisplayValue: 100)
        case .eclipse:
            return .percentage(defaultDisplayValue: 100)
        case .nourish:
            return .percentage(defaultDisplayValue: 50)
        case .xata:
            return .percentage(defaultDisplayValue: 50)
        case .toxicLash:
            return .percentage(defaultDisplayValue: 30)
        case .flatCriticalChance:
            return .percentage(defaultDisplayValue: 50)
        case .madurai:
            return .toggle
        }
    }

    public var acceptsDisplayPercentage: Bool {
        inputContract.acceptsDisplayPercentage
    }

    public var defaultDisplayValue: Double {
        inputContract.defaultDisplayValue
    }

    /// Converts the presentation value to the stable ScenarioEffects contract.
    /// Percentage-bearing website controls use display units (100 = 1.0);
    /// Madurai is a switch and therefore contributes one enabled flag.
    public func inputValue(fromDisplayValue value: Double) -> Double {
        inputContract.inputValue(fromDisplayValue: value)
    }
}

/// A non-formula contract shared by native frontends and persisted inputs.
/// `percentage` uses website display units (100 means 1.0 in DamageKit), while
/// `toggle` is represented as zero or one in the serializable value map.
public enum ScenarioEffectInputContract: Sendable, Equatable {
    case percentage(defaultDisplayValue: Double)
    case toggle

    public var acceptsDisplayPercentage: Bool {
        if case .percentage = self { return true }
        return false
    }

    public var defaultDisplayValue: Double {
        switch self {
        case .percentage(let value): return value
        case .toggle: return 1
        }
    }

    public func inputValue(fromDisplayValue value: Double) -> Double {
        switch self {
        case .percentage:
            return value / 100
        case .toggle:
            return value > 0 ? 1 : 0
        }
    }
}

/// Values for named environment effects.
///
/// This deliberately stores an ID-to-value map instead of placing one formula
/// field per SwiftUI control. The presentation layer can add, remove, search,
/// or localize a selectable effect without deciding where it belongs in the
/// damage equation. Values are decimal ratios (`0.30` = +30%) and their
/// meaning is resolved only by `BuildResolver`.
public struct ScenarioEffects: Codable, Sendable, Equatable {
    /// Stored as string keys so its JSON contract stays an ordinary object
    /// (`{"roar": 0.3}`), rather than Swift's array representation for a
    /// dictionary whose key is an enum. Formula code accesses it only through
    /// the typed `ScenarioEffectID` API below.
    public var values: [String: Double]

    public init(values: [ScenarioEffectID: Double] = [:]) {
        self.init(rawValues: Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }))
    }

    public init(rawValues: [String: Double]) {
        self.values = rawValues.filter { _, value in value.isFinite && abs(value) > .ulpOfOne }
    }

    /// Compatibility initializer for saved builds and the first parity
    /// fixtures. New callers should pass `values:` keyed by `ScenarioEffectID`.
    public init(roarFactionBonus: Double = 0, nourishViralBonus: Double = 0,
                flatCriticalChance: Double = 0) {
        self.init(values: [
            .roar: roarFactionBonus,
            .nourish: nourishViralBonus,
            .flatCriticalChance: flatCriticalChance,
        ])
    }

    public func value(for effect: ScenarioEffectID) -> Double {
        values[effect.rawValue] ?? 0
    }

    // These read-only aliases keep existing JSON consumers source-compatible.
    // The formula code below uses `value(for:)` so only the core maps an ID to
    // a calculation pool.
    public var roarFactionBonus: Double { value(for: .roar) }
    public var nourishViralBonus: Double { value(for: .nourish) }
    public var flatCriticalChance: Double { value(for: .flatCriticalChance) }

    private enum CodingKeys: String, CodingKey {
        case values, roarFactionBonus, nourishViralBonus, flatCriticalChance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try c.decodeIfPresent([String: Double].self, forKey: .values) {
            self.init(rawValues: decoded)
            return
        }
        self.init(
            roarFactionBonus: try c.decodeIfPresent(Double.self, forKey: .roarFactionBonus) ?? 0,
            nourishViralBonus: try c.decodeIfPresent(Double.self, forKey: .nourishViralBonus) ?? 0,
            flatCriticalChance: try c.decodeIfPresent(Double.self, forKey: .flatCriticalChance) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(values, forKey: .values)
    }

    public static let none = ScenarioEffects()
}

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
    /// 翠绿执政官石增加的腐蚀状态层数上限；例如普通 +2 与 Tauforged +3 合计填 5。
    public var corrosiveStackCapBonus: Double
    /// 已激活的、按层数结算的武器 buff。键使用游戏显示名，例如
    /// `{"Galvanized Diffusion": 4, "Galvanized Shot": 3, "Cascadia Flare": 40}`。
    /// 这是战甲、同伴或先前击杀提供的武器环境状态，不会从武器配卡中臆测。
    public var conditionalModStacks: [String: Double]
    /// 可选的「目标状态种类数」手动覆盖。非 nil 时仅替代 Condition
    /// Overload / Gun CO 所读取的不同状态种类计数，不虚构对应状态的 DOT、
    /// Viral、Corrosive 等其它目标侧效果。这与 warframe-damage 的同名开关
    /// 一致：它覆盖动态统计，而不是额外叠加到动态统计上。
    public var manualStatusTypeCount: Double?
    /// 对应网站“所有 Mod 条件已满足”的总开关。条件 Mod 的具体层数仍由
    /// `conditionalModStacks` 表达；这个布尔值只保留网站会据此启停的全局项目，
    /// 例如自定义的每种状态基础伤害。
    public var allModConditionsMet: Bool
    /// Resolved Ability Strength. `1.0` means 100%. Strength-scaled weapon
    /// data and frame/companion actions consume it in BuildResolver; a client
    /// should derive this from the selected Warframe configuration rather than
    /// expose a duplicate free-form final-strength field.
    public var abilityStrength: Double
    /// 对应网站 “Damage per status multiplier is multiplicative” 开关。它不改变
    /// 状态层数，只决定每状态基础伤害是否与基础伤害池相乘。
    public var forceMultiplicativePerStatusDamage: Bool
    /// 网站“自定义属性”面板的输入。键必须是 `CustomStatKey.rawValue`；未知键在
    /// 结果 notes 中报告，不能静默被当成伤害加成。
    public var customStats: [String: Double]
    /// 网站同名环境开关中、已经完成结算位置验证的命名效果。
    public var scenarioEffects: ScenarioEffects
    /// 用户在武器页面上明确勾选、要共用同一状态时间线的攻击段组合。
    ///
    /// 武器数据里的 `comb` 只是可选组合清单，并不表示网站默认把所有攻击段
    /// 合并。空数组就是网站初始状态：每段攻击分别计算；只有这里列出的合法
    /// 组合才会共享同一次命中的状态池。
    public var combinedAttackGroups: [[Int]]
    /// 网站“潜行加成”开关。DamageKit 只在近战武器上应用它；枪械保持网站的
    /// 无效果行为。
    public var stealth: Bool
    /// 网站“重击”开关。它只改变近战攻击段：使用源数据中的重击动作表、
    /// 重击专属 Mod action 和连击消耗时间线；非近战武器保持原样。
    public var heavyAttack: Bool
    /// 网站重击选项的“从第几倍连击开始”数值。它是倍率（12 表示 12x），
    /// 不是前端预乘到伤害上的百分比。
    public var heavyAttackStartingCombo: Double
    /// 网站“轻击连击倍率”的可选输入。nil 表示该开关未启用；有值时只供
    /// `crit_chance_per_combo` / `status_chance_by_combo` 等核心 action 读取，
    /// 不会被输入层直接当成伤害倍率。
    public var meleeComboMultiplier: Double?
    /// 网站“技能连击倍率”的可选输入。只对武器数据 `type == Exalted Weapon`
    /// 的攻击生效；其最终乘法位置在 BuildResolver / WeaponSimulator，而不是
    /// 前端。nil 表示网站开关未启用。
    public var abilityComboMultiplier: Double?
    /// 网站“狙击连击倍率”的可选覆盖。nil 表示开关未启用；带 `sniperCombo`
    /// 标记的攻击仍保留网站固有的 1.5x 默认值。
    public var sniperComboMultiplier: Double?
    public var headshot: Bool
    public var headshotMultiplier: Double
    /// 到目标的距离；nil 表示不受伤害衰减影响。
    public var distance: Double?
    /// 是否在弱点（Primary Acuity 这类条件 mod 需要）。
    public var weakPoint: Bool
    public var warframe: WarframeBuffs
    /// 战甲 Mod、同伴 Mod 和任务环境等在本次射击开始时已生效的来源。
    public var environment: EnvironmentEffects

    public init(window: Double = 20, steelPath: Bool = false, eximus: Bool = false,
                squadSize: Int = 1, armorStrip: Double = 0, externalViralStacks: Double = 0,
                corrosiveStackCapBonus: Double = 0,
                conditionalModStacks: [String: Double] = [:],
                manualStatusTypeCount: Double? = nil,
                allModConditionsMet: Bool = true,
                abilityStrength: Double = 1,
                forceMultiplicativePerStatusDamage: Bool = false,
                customStats: [String: Double] = [:],
                scenarioEffects: ScenarioEffects = .none,
                combinedAttackGroups: [[Int]] = [],
                stealth: Bool = false,
                heavyAttack: Bool = false,
                heavyAttackStartingCombo: Double = 12,
                meleeComboMultiplier: Double? = 12,
                abilityComboMultiplier: Double? = nil,
                sniperComboMultiplier: Double? = nil,
                headshot: Bool = false, headshotMultiplier: Double = Rules.defaultHeadshotMultiplier,
                distance: Double? = nil, weakPoint: Bool = false,
                warframe: WarframeBuffs = .none,
                environment: EnvironmentEffects = .none) {
        self.window = window
        self.steelPath = steelPath
        self.eximus = eximus
        self.squadSize = squadSize
        self.armorStrip = armorStrip
        self.externalViralStacks = externalViralStacks
        self.corrosiveStackCapBonus = corrosiveStackCapBonus
        self.conditionalModStacks = conditionalModStacks
        self.manualStatusTypeCount = manualStatusTypeCount
        self.allModConditionsMet = allModConditionsMet
        self.abilityStrength = abilityStrength
        self.forceMultiplicativePerStatusDamage = forceMultiplicativePerStatusDamage
        self.customStats = customStats
        self.scenarioEffects = scenarioEffects
        self.combinedAttackGroups = combinedAttackGroups
        self.stealth = stealth
        self.heavyAttack = heavyAttack
        self.heavyAttackStartingCombo = heavyAttackStartingCombo
        self.meleeComboMultiplier = meleeComboMultiplier
        self.abilityComboMultiplier = abilityComboMultiplier
        self.sniperComboMultiplier = sniperComboMultiplier
        self.headshot = headshot
        self.headshotMultiplier = headshotMultiplier
        self.distance = distance
        self.weakPoint = weakPoint
        self.warframe = warframe
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case window, steelPath, eximus, squadSize, armorStrip, externalViralStacks, corrosiveStackCapBonus
        case conditionalModStacks, manualStatusTypeCount, allModConditionsMet, abilityStrength
        case forceMultiplicativePerStatusDamage, customStats, scenarioEffects, combinedAttackGroups, stealth
        case heavyAttack, heavyAttackStartingCombo, meleeComboMultiplier, abilityComboMultiplier, sniperComboMultiplier
        case headshot, headshotMultiplier, distance, weakPoint, warframe, environment
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
        corrosiveStackCapBonus = try c.decodeIfPresent(Double.self, forKey: .corrosiveStackCapBonus) ?? 0
        conditionalModStacks = try c.decodeIfPresent([String: Double].self, forKey: .conditionalModStacks) ?? [:]
        manualStatusTypeCount = try c.decodeIfPresent(Double.self, forKey: .manualStatusTypeCount)
        allModConditionsMet = try c.decodeIfPresent(Bool.self, forKey: .allModConditionsMet) ?? true
        abilityStrength = try c.decodeIfPresent(Double.self, forKey: .abilityStrength) ?? 1
        forceMultiplicativePerStatusDamage = try c.decodeIfPresent(Bool.self,
                                                                     forKey: .forceMultiplicativePerStatusDamage) ?? false
        customStats = try c.decodeIfPresent([String: Double].self, forKey: .customStats) ?? [:]
        scenarioEffects = try c.decodeIfPresent(ScenarioEffects.self, forKey: .scenarioEffects) ?? .none
        combinedAttackGroups = try c.decodeIfPresent([[Int]].self, forKey: .combinedAttackGroups) ?? []
        stealth = try c.decodeIfPresent(Bool.self, forKey: .stealth) ?? false
        heavyAttack = try c.decodeIfPresent(Bool.self, forKey: .heavyAttack) ?? false
        heavyAttackStartingCombo = try c.decodeIfPresent(Double.self, forKey: .heavyAttackStartingCombo) ?? 12
        // Missing is an old saved input and retains the website's historical
        // default (12x); an explicit JSON null is the meaningful “off” state.
        if c.contains(.meleeComboMultiplier) {
            meleeComboMultiplier = try c.decodeIfPresent(Double.self, forKey: .meleeComboMultiplier)
        } else {
            meleeComboMultiplier = 12
        }
        abilityComboMultiplier = try c.decodeIfPresent(Double.self, forKey: .abilityComboMultiplier)
        sniperComboMultiplier = try c.decodeIfPresent(Double.self, forKey: .sniperComboMultiplier)
        headshot = try c.decodeIfPresent(Bool.self, forKey: .headshot) ?? false
        headshotMultiplier = try c.decodeIfPresent(Double.self, forKey: .headshotMultiplier)
            ?? Rules.defaultHeadshotMultiplier
        distance = try c.decodeIfPresent(Double.self, forKey: .distance)
        weakPoint = try c.decodeIfPresent(Bool.self, forKey: .weakPoint) ?? false
        warframe = try c.decodeIfPresent(WarframeBuffs.self, forKey: .warframe) ?? .none
        environment = try c.decodeIfPresent(EnvironmentEffects.self, forKey: .environment) ?? .none
    }

    /// 存档键保留展示名，但 API 不要求调用方严格匹配大小写。
    public func conditionalStackCount(named name: String) -> Double {
        conditionalModStacks.first {
            $0.key.compare(name, options: [.caseInsensitive]) == .orderedSame
        }?.value ?? 0
    }

    /// Retrieves a typed custom-stat input without leaking string-key handling
    /// into the resolver's formula code.
    public func customStat(_ key: CustomStatKey) -> Double {
        customStats[key.rawValue] ?? 0
    }

    /// Values outside the website's declared custom-stat surface are surfaced
    /// to the result instead of being ignored as though they had been applied.
    public var unrecognizedCustomStatKeys: [String] {
        let known = Set(CustomStatKey.allCases.map(\.rawValue))
        return customStats.keys.filter { !known.contains($0) }.sorted()
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
    /// 完整时间窗口内的未减免平均输出；即使这个具体目标先死亡，也不会把
    /// 剩余窗口的武器输出清零。目标实际承伤与 TTK 见 `layers`。
    public var dps: Double
    /// 完整时间窗口内的未减免直伤输出。
    public var directDamage: Double
    /// 完整时间窗口内由该武器产生的未减免 DOT 输出。
    public var dotDamage: Double
    /// 命中直伤 + DOT 的未减免伤害，按类型分解（扣减伤之前）。
    public var rawByType: [String: Double]
    /// 在相同状态时间线中，持续作用于目标生命层的平均 DPS。
    ///
    /// 与 `dps` 不同，这里已经计入属性抗性、护甲、Corrosive/Heat 剥甲、
    /// Viral 等目标侧倍率；目标本身死亡后仍使用同一状态继续计算到窗口末尾，
    /// 因而可与伤害网站的 Armor/Health DPS 直接作同口径比较。
    public var targetDps: Double
    /// 与 `targetDps` 使用同一目标状态时间线，但只统计即时命中。
    ///
    /// 伤害网站前端的随机队列 DPS 不把普通 DOT 尾伤混入这一栏；因此这是
    /// 对拍时与其直击指标对应的连续期望量。它仍然不是随机队列的中位数。
    public var targetDirectDps: Double
    /// `targetDps` 对应的生命层直伤总量（不受目标有限生命值截断）。
    public var targetDirectDamage: Double
    /// `targetDps` 对应的生命层 DOT 总量（不受目标有限生命值截断）。
    public var targetDotDamage: Double
    /// `targetDirectDamage + targetDotDamage` 按伤害类型分解。
    public var targetByType: [String: Double]
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
