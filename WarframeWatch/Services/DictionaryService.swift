import Foundation

public final class DictionaryService {
    public static let shared = DictionaryService()
    
    // In-memory dictionaries
    private var nodes: [String: [String: String]] = [:]
    private var missionTypes: [String: String] = [:]
    private var factions: [String: String] = [:]
    private var syndicates: [String: String] = [:]
    private var sortieModifiers: [String: String] = [:]
    private var sortieDesc: [String: String] = [:]
    private var sortieBosses: [String: [String: String]] = [:]
    private var tiers: [String: String] = [:]
    private var items: [String: String] = [:]
    private var itemRules: [String: String] = [:]
    private var hubNames: [String: String] = [:]
    private var lang: [String: String] = [:]
    private var upgrades: [String: String] = [:]
    
    public init() {
        loadDictionary()
    }
    
    private func loadDictionary() {
        // Attempt to load from Bundle
        if let url = Bundle.main.url(forResource: "DefaultDict", withExtension: "json") ??
                     Bundle(for: DictionaryService.self).url(forResource: "DefaultDict", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parseDict(json)
            return
        }
        
        // Fallback: minimal built-ins
        setupFallbackDict()
    }
    
    private func parseDict(_ json: [String: Any]) {
        if let n = json["nodes"] as? [String: [String: String]] { self.nodes = n }
        if let mt = json["missionTypes"] as? [String: String] { self.missionTypes = mt }
        if let f = json["factions"] as? [String: String] { self.factions = f }
        if let s = json["syndicates"] as? [String: Any] {
            var res: [String: String] = [:]
            for (k, v) in s {
                if let str = v as? String { res[k] = str }
                else if let d = v as? [String: Any], let name = d["name"] as? String { res[k] = name }
            }
            self.syndicates = res
        }
        if let sm = json["sortieModifiers"] as? [String: String] { self.sortieModifiers = sm }
        if let sd = json["sortieDesc"] as? [String: String] { self.sortieDesc = sd }
        if let sb = json["sortieBosses"] as? [String: [String: String]] { self.sortieBosses = sb }
        if let t = json["tiers"] as? [String: String] { self.tiers = t }
        if let it = json["items"] as? [String: String] { self.items = it }
        if let ir = json["itemRules"] as? [String: String] { self.itemRules = ir }
        if let hn = json["hubNames"] as? [String: String] { self.hubNames = hn }
        if let lg = json["lang"] as? [String: String] { self.lang = lg }
        if let up = json["upgrades"] as? [String: String] { self.upgrades = up }
    }
    
    private func setupFallbackDict() {
        tiers = [
            "VoidT1": "古纪", "VoidT2": "前纪", "VoidT3": "中纪",
            "VoidT4": "后纪", "VoidT5": "安魂", "VoidT6": "全能"
        ]
        factions = [
            "FC_CORPUS": "Corpus 科普斯", "FC_GRINEER": "Grineer 克隆尼",
            "FC_INFESTATION": "Infested 疫变体", "FC_CORRUPTED": "堕落者",
            "FC_OROKIN": "奥罗金", "FC_SENTIENT": "Sentient 心智者",
            "FC_TENNO": "Tenno 天诺", "FC_MITW": "墙中人", "FC_NARMER": "Narmer 纳尔默"
        ]
        missionTypes = [
            "MT_DEFENSE": "防御", "MT_SURVIVAL": "生存", "MT_CAPTURE": "捕获",
            "MT_EXTERMINATION": "歼灭", "MT_MOBILE_DEFENSE": "移动防御",
            "MT_SABOTAGE": "破坏", "MT_ASSASSINATION": "刺杀", "MT_RESCUE": "救援",
            "MT_INTEL": "间谍", "MT_DISRUPTION": "中断", "MT_EXCAVATE": "挖掘",
            "MT_VOID_CASCADE": "虚空覆涌", "MT_CORRUPTION": "虚空洪流",
            "MT_ALCHEMY": "元素转换", "MT_LANDSCAPE": "自由探索"
        ]
    }
    
    // MARK: - Lookups
    
    public func nodeName(_ id: String?) -> String {
        guard let id = id, !id.isEmpty else { return "未知节点" }
        if let info = nodes[id], let n = info["n"], !n.isEmpty {
            return n
        }
        if let hub = hubNames[id] {
            return hub
        }
        return id
    }
    
    public func missionType(_ type: String?) -> String {
        guard let type = type, !type.isEmpty else { return "未知任务" }
        return missionTypes[type] ?? type.replacingOccurrences(of: "MT_", with: "")
    }
    
    public func faction(_ f: String?) -> String {
        guard let f = f, !f.isEmpty else { return "未知派系" }
        return factions[f] ?? f.replacingOccurrences(of: "FC_", with: "")
    }
    
    public func syndicate(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "未知集团" }
        return syndicates[s] ?? s.replacingOccurrences(of: "Syndicate", with: "")
    }
    
    public func sortieModifierName(_ m: String?) -> String {
        guard let m = m, !m.isEmpty else { return "未知强化" }
        return sortieModifiers[m] ?? m.replacingOccurrences(of: "SORTIE_MODIFIER_", with: "")
    }
    
    public func sortieModifierDesc(_ m: String?) -> String {
        guard let m = m else { return "" }
        return sortieDesc[m] ?? ""
    }
    
    public func bossName(_ b: String?) -> String {
        guard let b = b, !b.isEmpty else { return "未知首领" }
        if let info = sortieBosses[b], let name = info["name"] {
            return name
        }
        return b.replacingOccurrences(of: "SORTIE_BOSS_", with: "")
    }
    
    public func tierName(_ t: String?) -> String {
        guard let t = t, !t.isEmpty else { return "未知纪元" }
        if let name = tiers[t] {
            return "\(name) (\(t))"
        }
        return t
    }
    
    public func upgradeName(_ u: String?) -> String {
        guard let u = u, !u.isEmpty else { return "未知增益" }
        return upgrades[u] ?? u
    }
    
    public func localizedDesc(_ tag: String?) -> String {
        guard let tag = tag, !tag.isEmpty else { return "" }
        if let str = lang[tag] { return str }
        let last = tag.split(separator: "/").last.map(String.init) ?? tag
        return humanize(last)
    }
    
    public func itemName(_ path: String?) -> String {
        guard let path = path, !path.isEmpty else { return "—" }
        if let exact = items[path] { return exact }
        let last = path.split(separator: "/").last.map(String.init) ?? path
        if let exactLast = items[last] { return exactLast }
        
        // Rule match
        for (prefix, ruleLabel) in itemRules {
            if path.contains(prefix) {
                return "\(ruleLabel) · \(humanize(last))"
            }
        }
        return humanize(last)
    }
    
    public func humanize(_ s: String) -> String {
        var result = ""
        for char in s {
            if char.isUppercase && !result.isEmpty && result.last != " " {
                result.append(" ")
            }
            if char == "_" {
                result.append(" ")
            } else {
                result.append(char)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
