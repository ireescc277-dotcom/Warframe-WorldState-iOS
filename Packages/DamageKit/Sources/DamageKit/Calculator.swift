import Foundation

/// 站点离线数据目录（`server/site`）的读取器。
///
/// 只读，不改动仓库里的数据文件。
public struct DataStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 仓库中受版本控制的原始站点资料：`<repo>/server/site`。
    ///
    /// 这里不把开发机生成的 `web/app/site` 当作默认值。后者是浏览器离线包，
    /// 不会进入干净的 CI checkout；所有原生计算和对照都应直接读取同一份
    /// `server/site` 数据。
    public static func defaultRoot(relativeTo url: URL) -> URL {
        url.appendingPathComponent("server/site")
    }

    /// 旧浏览器离线包的兼容位置。仅在调用方明确处于一个仍保留该生成物的
    /// 开发目录时作为 `discoverRoot` 的回退，绝不优先于 `server/site`。
    public static func legacyBrowserBundleRoot(relativeTo url: URL) -> URL {
        url.appendingPathComponent("web/app/site")
    }

    /// 从当前目录向上寻找 monorepo 的离线数据根。CLI 用这个方法，避免把
    /// `Packages/DamageKit` 当成仓库根而静默读到不存在的目录。
    public static func discoverRoot(startingAt directory: URL) -> URL? {
        var cursor = directory.standardizedFileURL
        while true {
            let candidates = [
                defaultRoot(relativeTo: cursor),
                legacyBrowserBundleRoot(relativeTo: cursor),
            ]
            if let candidate = candidates.first(where: hasRequiredData(at:)) {
                return candidate
            }

            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { return nil }
            cursor = parent
        }
    }

    public static func hasRequiredData(at root: URL) -> Bool {
        let fm = FileManager.default
        let hasWeaponManifest = fm.fileExists(atPath: root.appendingPathComponent("weapons.json").path)
            || fm.fileExists(atPath: root.appendingPathComponent("weapons-list.json").path)
        return hasWeaponManifest
            && fm.fileExists(atPath: root.appendingPathComponent("weapons").path)
            && fm.fileExists(atPath: root.appendingPathComponent("data/json/enemies-min.json").path)
    }

    public func weapon(named name: String) throws -> Weapon {
        guard let url = weaponURL(named: name) else {
            throw DamageKitError.weaponNotFound(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Weapon.self, from: data)
    }

    /// 首先走常见的直接文件名；导出文件也会移除括号、`&` 等字符，所以
    /// fallback 用同一份名称的字母数字规范化键定位，不能只替换空格。
    private func weaponURL(named name: String) -> URL? {
        let directory = root.appendingPathComponent("weapons")
        let directName = name.replacingOccurrences(of: " ", with: "_") + ".json"
        let direct = directory.appendingPathComponent(directName)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        // `server/site/weapons.json` is the source site's exact name-to-file
        // map.  Use it before the broad normalized fallback so punctuation,
        // parentheses and special weapon names select the same record as the
        // website itself.
        let manifest = root.appendingPathComponent("weapons.json")
        if let data = try? Data(contentsOf: manifest),
           let entries = try? JSONDecoder().decode([String: String].self, from: data),
           let filename = entries[name] {
            let mapped = directory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: mapped.path) { return mapped }
        }

        let key = Self.weaponLookupKey(name)
        guard !key.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else { return nil }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { Self.weaponLookupKey($0.deletingPathExtension().lastPathComponent) == key }
    }

    private static func weaponLookupKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
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
        struct Entry: Decodable { let n: String }
        let generatedIndex = root.appendingPathComponent("weapons-list.json")
        if FileManager.default.fileExists(atPath: generatedIndex.path) {
            let data = try Data(contentsOf: generatedIndex)
            return try JSONDecoder().decode([Entry].self, from: data).map(\.n)
        }

        // The checked-in website source has a compact dictionary instead of
        // the generated browser bundle's array.  It is sufficient for the
        // CLI's name listing and keeps native tooling independent of ignored
        // build artefacts.
        let manifest = root.appendingPathComponent("weapons.json")
        let data = try Data(contentsOf: manifest)
        return try JSONDecoder().decode([String: String].self, from: data).keys.sorted()
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
    public var weapon: RefOrValue<Weapon>?
    /// 直接按 DE 背包武器实例导入；与 `weapon` 二选一。
    public var ownedWeapon: OwnedWeaponReference?
    public var enemy: RefOrValue<Enemy>
    public var level: Int
    public var build: Build
    public var options: Options

    private enum CodingKeys: String, CodingKey {
        case weapon, ownedWeapon, enemy, level, build, options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weapon = try c.decodeIfPresent(RefOrValue<Weapon>.self, forKey: .weapon)
        ownedWeapon = try c.decodeIfPresent(OwnedWeaponReference.self, forKey: .ownedWeapon)
        enemy = try c.decode(RefOrValue<Enemy>.self, forKey: .enemy)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 100
        build = try c.decodeIfPresent(Build.self, forKey: .build) ?? Build()
        options = try c.decodeIfPresent(Options.self, forKey: .options) ?? Options()
    }

    public func resolve(using store: DataStore?) throws -> DamageInput {
        let w: Weapon
        let resolvedBuild: Build
        if let ownedWeapon {
            guard weapon == nil else {
                throw DamageKitError.invalidRequest("weapon 与 ownedWeapon 不能同时提供")
            }
            guard let store else { throw DamageKitError.weaponNotFound(ownedWeapon.weaponId) }
            let owned = try InventoryAdapter(snapshotURL: URL(fileURLWithPath: ownedWeapon.snapshot))
                .resolve(ownedWeapon, using: store)
            w = owned.weapon
            resolvedBuild = owned.build
        } else if let weapon {
            switch weapon {
            case .value(let v): w = v
            case .reference(let name):
                guard let store else { throw DamageKitError.weaponNotFound(name) }
                w = try store.weapon(named: name)
            }
            resolvedBuild = build
        } else {
            throw DamageKitError.invalidRequest("必须提供 weapon 或 ownedWeapon")
        }
        let e: Enemy
        switch enemy {
        case .value(let v): e = v
        case .reference(let name):
            guard let store else { throw DamageKitError.enemyNotFound(name) }
            e = try store.enemy(named: name)
        }
        return DamageInput(weapon: w, enemy: e, level: level, build: resolvedBuild, options: options)
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
        let groups = Calculator.groups(weapon: input.weapon,
                                       count: resolved.count,
                                       selected: input.options.combinedAttackGroups)

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

    /// 网站把 `comb` 作为可勾选的候选组合，而不是默认行为。只有 `selected`
    /// 中的、且确实出现在武器候选清单里的组合会共享状态池；其他攻击段各自
    /// 独立。这避免把“直击 + 爆炸可合并”误当成“直击 + 爆炸总是同时命中”。
    public static func groups(weapon: Weapon, count: Int, selected: [[Int]]) -> [[Int]] {
        var used = Set<Int>()
        var groups: [[Int]] = []

        let available = (weapon.comb ?? []).compactMap { raw -> [Int]? in
            let members = raw.filter { $0 >= 0 && $0 < count }
            guard members.count == raw.count,
                  members.count > 1,
                  Set(members).count == members.count else { return nil }
            return members
        }

        for request in selected {
            let requestSet = Set(request)
            guard request.count > 1,
                  requestSet.count == request.count,
                  let members = available.first(where: {
                      $0.count == request.count && Set($0) == requestSet
                  }) else { continue }
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
