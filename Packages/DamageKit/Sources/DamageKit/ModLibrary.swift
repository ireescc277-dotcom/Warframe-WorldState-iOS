import Foundation

/// `mods.json` 里的一条 mod。字段按站点数据原样保留，`action` 是它的效果描述。
public struct ModDefinition: Decodable, Sendable, Equatable {
    public var name: String
    public var tags: [String]?
    public var type: String?
    public var uncomp: [String]?
    public var action: [String: JSONValue]?
}

/// mod 数据表。
///
/// 数据来源：`web/app/site/min.js` 里的 `modsProps`，由 `scripts/export_mods.js`
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

    public init(definitions: [ModDefinition]) {
        self.definitions = definitions
        var map: [String: ModDefinition] = [:]
        for d in definitions { map[d.name.lowercased()] = d }
        byName = map
    }

    public static func bundled() throws -> ModLibrary {
        guard let url = Bundle.module.url(forResource: "mods", withExtension: "json") else {
            throw DamageKitError.missingResource("mods.json")
        }
        return try load(from: url)
    }

    public static func load(from url: URL) throws -> ModLibrary {
        let data = try Data(contentsOf: url)
        let defs = try JSONDecoder().decode([ModDefinition].self, from: data)
        return ModLibrary(definitions: defs)
    }

    public func mod(named name: String) -> ModDefinition? {
        byName[name.lowercased()]
    }
}

public enum DamageKitError: Error, CustomStringConvertible {
    case missingResource(String)
    case weaponNotFound(String)
    case enemyNotFound(String)
    case modNotFound(String)

    public var description: String {
        switch self {
        case .missingResource(let s): return "缺少资源: \(s)"
        case .weaponNotFound(let s): return "找不到武器: \(s)"
        case .enemyNotFound(let s): return "找不到敌人: \(s)"
        case .modNotFound(let s): return "找不到 mod: \(s)"
        }
    }
}
