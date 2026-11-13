import Foundation

/// `mods.json` 里的一条 mod。字段按站点数据原样保留，`action` 是它的效果描述。
public struct ModDefinition: Decodable, Sendable, Equatable {
    public var name: String
    /// 站点 Mod 图标的文件名，例如 `Serration.webp`。
    ///
    /// 计算内核不依赖图片；保留它是为了让原生界面能展示与站点相同的卡片。
    public var image: String?
    public var tags: [String]?
    public var type: String?
    public var info: String?
    /// 套装规则保持为原始 JSON，避免在未实现其公式时丢掉来源数据。
    public var set: JSONValue?
    public var shardType: String?
    public var trigger: String?
    public var onKill: Bool?
    public var preference: Double?
    public var uncomp: [String]?
    public var incompatibleTag: JSONValue?
    public var action: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case name, tags, type, info, set, trigger, action, uncomp
        case image = "img"
        case shardType
        case onKill = "onkill"
        case preference = "prefer"
        case incompatibleTag = "uncomptag"
    }
}

/// mod 数据表。
///
/// 数据来源：`server/site/min.js` 里的 `modsProps`，由 `scripts/export_mods.js`
/// 以字面量方式导出为 `Resources/mods.json`（只取数据，不碰任何函数实现）。
public final class ModLibrary: @unchecked Sendable {
    public static let shared: ModLibrary = {
        do {
            return try ModLibrary.bundled()
        } catch {
            return ModLibrary(definitions: [])
        }
    }()

    public let definitions: [ModDefinition]
    public let byName: [String: ModDefinition]
    /// 只有原始 `WITH_COND` 数值无法表达的层数语义：例如“2.3 是满层总值”
    /// 与“4.8 是额外加成”是两种不同公式。该表将这个语义从解析代码中移出。
    public let conditionalRulesByName: [String: ConditionalEffectRule]
    /// Source order of every stance Mod's combo list.  The Mod action itself
    /// remains the source for numerical combo values; this index only retains
    /// the UI-visible order that Swift dictionaries otherwise discard.
    public let stanceComboOrderByMod: [String: [String]]

    public init(definitions: [ModDefinition], conditionalRules: [ConditionalEffectRule] = [],
                stanceComboOrder: [String: [String]] = [:]) {
        self.definitions = definitions
        var map: [String: ModDefinition] = [:]
        for d in definitions { map[d.name.lowercased()] = d }
        byName = map

        var ruleMap: [String: ConditionalEffectRule] = [:]
        for rule in conditionalRules { ruleMap[rule.mod.lowercased()] = rule }
        conditionalRulesByName = ruleMap
        var comboOrder: [String: [String]] = [:]
        for (name, names) in stanceComboOrder {
            comboOrder[name.lowercased()] = names
        }
        stanceComboOrderByMod = comboOrder
    }

    public static func bundled() throws -> ModLibrary {
        guard let url = Bundle.module.url(forResource: "mods", withExtension: "json") else {
            throw DamageKitError.missingResource("mods.json")
        }
        guard let rulesURL = Bundle.module.url(forResource: "conditional-effects", withExtension: "json") else {
            throw DamageKitError.missingResource("conditional-effects.json")
        }
        guard let stanceOrderURL = Bundle.module.url(forResource: "stance-combo-order", withExtension: "json") else {
            throw DamageKitError.missingResource("stance-combo-order.json")
        }
        let definitions = try load(from: url).definitions + Self.supplementalDefinitions()
        let ruleData = try Data(contentsOf: rulesURL)
        let rules = try JSONDecoder().decode([ConditionalEffectRule].self, from: ruleData)
            + Self.supplementalConditionalRules()
        let stanceOrderData = try Data(contentsOf: stanceOrderURL)
        let stanceOrder = try JSONDecoder().decode([String: [String]].self, from: stanceOrderData)
        return ModLibrary(definitions: definitions, conditionalRules: rules,
                          stanceComboOrder: stanceOrder)
    }

    private static func supplementalDefinitions() -> [ModDefinition] {
        // Supplemental cards missing from upstream server/site `mods.json` (kept
        // outside `mods.json` so `verify_mod_data_parity.js` preserves exact parity).
        let json = #"""
        [
          {"name":"Bane of Infested","tags":["rifle","shotgun","sniper","primary"],"type":"","action":{"SMITE":{"Infested":0.3}}},
          {"name":"Bane of Corpus","tags":["rifle","shotgun","sniper","primary"],"type":"","action":{"SMITE":{"Corpus":0.3}}},
          {"name":"Bane of Orokin","tags":["rifle","shotgun","sniper","primary"],"type":"","action":{"SMITE":{"Orokin":0.3}}},
          {"name":"Primed Bane of Orokin","tags":["rifle","shotgun","sniper","primary"],"type":"","action":{"SMITE":{"Orokin":0.55}}},
          {"name":"Melee Animosity","tags":["melee"],"type":"weapon_mist","info":"On Melee Hit: Gain 42% Critical Chance on your next Heavy Attack, up to 420%.","action":{"WITH_COND":{"heavy_crit_chance":4.2}}},
          {"name":"Melee Assimilation","tags":["melee"],"type":"weapon_mist","info":"On Shield Break: +150% Melee Damage on Heavy Attack.","action":{"WITH_COND":{"base_heavy":1.5}}},
          {"name":"Cascadia Accuracy","tags":["secondary"],"type":"weapon_mist","info":"On Roll: +300% Critical Chance on Weak Point Hits for 4s.","action":{"WITH_COND":{"crit_chance_weakp":3.0}}},
          {"name":"Theorem Demulcent","tags":["frame"],"type":"frame_mist","info":"Standing in a zone created by a Residual Arcane increases weapon damage by 12%/s stacking up to 15x.","action":{"WITH_COND":{"base":1.8}}}
        ]
        """#
        guard let data = json.data(using: .utf8),
              let defs = try? JSONDecoder().decode([ModDefinition].self, from: data) else {
            return []
        }
        return defs
    }

    private static func supplementalConditionalRules() -> [ConditionalEffectRule] {
        let json = #"""
        [
          {"mod":"Melee Animosity","maxStacks":10,"mode":"scaledConditionalValue","keys":["heavy_crit_chance"],"inputLabel":"近战命中层数"},
          {"mod":"Theorem Demulcent","maxStacks":15,"mode":"scaledConditionalValue","keys":["base"],"inputLabel":"残留区域秒数"}
        ]
        """#
        guard let data = json.data(using: .utf8),
              let rules = try? JSONDecoder().decode([ConditionalEffectRule].self, from: data) else {
            return []
        }
        return rules
    }

    public static func load(from url: URL) throws -> ModLibrary {
        let data = try Data(contentsOf: url)
        let defs = try JSONDecoder().decode([ModDefinition].self, from: data)
        return ModLibrary(definitions: defs)
    }

    public func mod(named name: String) -> ModDefinition? {
        byName[name.lowercased()]
    }

    public func conditionalRule(named name: String) -> ConditionalEffectRule? {
        conditionalRulesByName[name.lowercased()]
    }

    public func stanceComboNames(for modName: String) -> [String] {
        stanceComboOrderByMod[modName.lowercased()] ?? []
    }
}

public enum DamageKitError: Error, CustomStringConvertible {
    case missingResource(String)
    case weaponNotFound(String)
    case enemyNotFound(String)
    case modNotFound(String)
    case invalidRequest(String)

    public var description: String {
        switch self {
        case .missingResource(let s): return "缺少资源: \(s)"
        case .weaponNotFound(let s): return "找不到武器: \(s)"
        case .enemyNotFound(let s): return "找不到敌人: \(s)"
        case .modNotFound(let s): return "找不到 mod: \(s)"
        case .invalidRequest(let s): return "输入无效: \(s)"
        }
    }
}
