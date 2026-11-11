import Foundation

/// 站点离线数据目录（`web/app/site`）的读取器。
///
/// 只读，不改动仓库里的数据文件。
public struct DataStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 仓库默认布局：`<repo>/web/app/site`。
    public static func defaultRoot(relativeTo url: URL) -> URL {
        url.appendingPathComponent("web/app/site")
    }

    public func weapon(named name: String) throws -> Weapon {
        let fileName = name.replacingOccurrences(of: " ", with: "_") + ".json"
        let url = root.appendingPathComponent("weapons").appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DamageKitError.weaponNotFound(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Weapon.self, from: data)
    }

    public func enemy(named name: String) throws -> Enemy {
        let url = root.appendingPathComponent("data/json/enemies-min.json")
        let data = try Data(contentsOf: url)
        let list = try JSONDecoder().decode([Enemy].self, from: data)
        guard let hit = list.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw DamageKitError.enemyNotFound(name)
        }
        return hit
    }

    public func enemyNames() throws -> [String] {
        let url = root.appendingPathComponent("data/json/enemies-min.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Enemy].self, from: data).map(\.name)
    }

    public func weaponNames() throws -> [String] {
        let url = root.appendingPathComponent("weapons-list.json")
        struct Entry: Decodable { let n: String }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Entry].self, from: data).map(\.n)
    }
}

/// 输入 JSON 里 `weapon` / `enemy` 既可以是名字，也可以是完整对象。
public enum RefOrValue<T: Decodable & Sendable>: Sendable {
    case reference(String)
    case value(T)

    public var reference: String? {
        if case .reference(let s) = self { return s }
        return nil
    }

    public var value: T? {
        if case .value(let v) = self { return v }
        return nil
    }
}

extension RefOrValue: Decodable {
    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let name = try? single.decode(String.self) {
            self = .reference(name)
            return
        }
        self = .value(try single.decode(T.self))
    }
}

/// 一次请求。用来承接 CLI 的输入文件。
public struct DamageRequest: Decodable, Sendable {
    public var weapon: RefOrValue<Weapon>
    public var enemy: RefOrValue<Enemy>
    public var level: Int
    public var build: Build
    public var options: Options

    private enum CodingKeys: String, CodingKey {
        case weapon, enemy, level, build, options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weapon = try c.decode(RefOrValue<Weapon>.self, forKey: .weapon)
        enemy = try c.decode(RefOrValue<Enemy>.self, forKey: .enemy)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 100
        build = try c.decodeIfPresent(Build.self, forKey: .build) ?? Build()
        options = try c.decodeIfPresent(Options.self, forKey: .options) ?? Options()
    }

    public func resolve(using store: DataStore?) throws -> DamageInput {
        let w: Weapon
        switch weapon {
        case .value(let v): w = v
        case .reference(let name):
            guard let store else { throw DamageKitError.weaponNotFound(name) }
            w = try store.weapon(named: name)
        }
        let e: Enemy
        switch enemy {
        case .value(let v): e = v
        case .reference(let name):
            guard let store else { throw DamageKitError.enemyNotFound(name) }
            e = try store.enemy(named: name)
        }
        return DamageInput(weapon: w, enemy: e, level: level, build: build, options: options)
    }
}

/// 入口：吃一份输入，吐出四层结果。
public struct Calculator: Sendable {
    public let store: DataStore?
    public let modLibrary: ModLibrary

    public init(store: DataStore? = nil, modLibrary: ModLibrary = .shared) {
        self.store = store
        self.modLibrary = modLibrary
    }

    /// 只做装配解析，不跑模拟。CLI 的 `--dump-resolved` 用它核对中间量。
    public func resolvedAttacks(_ input: DamageInput) -> [ResolvedAttack] {
        let profile = EnemyProfile(enemy: input.enemy, level: input.level, options: input.options)
        let resolver = BuildResolver(weapon: input.weapon,
                                     build: input.build,
                                     options: input.options,
                                     faction: profile.faction,
                                     library: modLibrary)
        return resolver.resolveAll()
    }

    public func evaluate(_ input: DamageInput) -> Result {
        let profile = EnemyProfile(enemy: input.enemy, level: input.level, options: input.options)
        let resolver = BuildResolver(weapon: input.weapon,
                                     build: input.build,
                                     options: input.options,
                                     faction: profile.faction,
                                     library: modLibrary)
        let resolved = resolver.resolveAll()
        let groups = Calculator.groups(weapon: input.weapon, count: resolved.count)

        var ordered = [(Int, AttackResult)]()
        for group in groups {
            let sim = WeaponSimulator(segments: group.map { resolved[$0] },
                                      enemy: profile,
                                      options: input.options)
            let results = sim.run()
            for (offset, result) in results.enumerated() {
                var r = result
                if profile.faction.canonical == "Neutral" {
                    r.notes.append("派系未能识别，抗性按 1.0 处理: \(input.enemy.faction)")
                }
                ordered.append((group[offset], r))
            }
        }
        ordered.sort { $0.0 < $1.0 }

        var notes = profile.notes
        if input.options.window < 1 || input.options.window > 60 {
            notes.append("窗口超过 1–60 的建议范围，已按输入值计算")
        }

        return Result(weapon: input.weapon.name,
                      enemy: input.enemy.name,
                      level: input.level,
                      window: input.options.window,
                      enemyStats: profile.stats,
                      attacks: ordered.map(\.1),
                      notes: notes)
    }

    /// `comb` 里成对的段是同一次开火出来的（直击 + 爆炸 / 毒云），
    /// 它们共享状态池；没进任何 pair 的段单独成组。
    public static func groups(weapon: Weapon, count: Int) -> [[Int]] {
        var used = Set<Int>()
        var groups: [[Int]] = []
        for pair in weapon.comb ?? [] {
            let members = pair.filter { $0 >= 0 && $0 < count }
            guard !members.isEmpty else { continue }
            if members.contains(where: { used.contains($0) }) { continue }
            members.forEach { used.insert($0) }
            groups.append(members)
        }
        for i in 0..<count where !used.contains(i) { groups.append([i]) }
        groups.sort { ($0.first ?? 0) < ($1.first ?? 0) }
        return groups
    }

    public func evaluate(_ request: DamageRequest) throws -> Result {
        evaluate(try request.resolve(using: store))
    }
}
