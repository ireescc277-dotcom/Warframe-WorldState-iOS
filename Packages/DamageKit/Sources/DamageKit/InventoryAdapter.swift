import Foundation

/// 背包里一把已经拥有的武器实例。`weaponId` 是 DE 背包对象的 ItemId，
/// 不是显示名称；因此同名武器、不同赤毒元素和不同配置不会混淆。
public struct OwnedWeaponReference: Codable, Sendable, Equatable {
    public var snapshot: String
    public var weaponId: String
    /// DE 的配置索引，A = 0、B = 1、C = 2。
    public var configIndex: Int

    public init(snapshot: String, weaponId: String, configIndex: Int = 0) {
        self.snapshot = snapshot
        self.weaponId = weaponId
        self.configIndex = configIndex
    }
}

/// 导入后仍保留槽位、等级和实例 ID，便于调用者检查“程序到底读了什么”。
public struct InstalledMod: Sendable, Equatable {
    public var slot: Int
    public var instanceId: String
    public var name: String
    public var rank: Int

    public init(slot: Int, instanceId: String, name: String, rank: Int) {
        self.slot = slot
        self.instanceId = instanceId
        self.name = name
        self.rank = rank
    }
}

public struct OwnedWeaponBuild: Sendable {
    public var itemId: String
    public var itemType: String
    public var configIndex: Int
    public var weapon: Weapon
    public var build: Build
    public var installedMods: [InstalledMod]

    public init(itemId: String, itemType: String, configIndex: Int, weapon: Weapon,
                build: Build, installedMods: [InstalledMod]) {
        self.itemId = itemId
        self.itemType = itemType
        self.configIndex = configIndex
        self.weapon = weapon
        self.build = build
        self.installedMods = installedMods
    }
}

public enum InventoryAdapterError: Error, CustomStringConvertible {
    case unreadableSnapshot(String)
    case malformedSnapshot(String)
    case weaponNotFound(String)
    case configNotFound(Int)
    case upgradeNotFound(String)
    case gameDataNotFound(String)
    case unsupportedModRank(name: String, rank: Int, maximum: Int)
    case unsupportedUpgrade(String)
    case rivenNotFound(String)

    public var description: String {
        switch self {
        case .unreadableSnapshot(let value): return "无法读取背包快照: \(value)"
        case .malformedSnapshot(let value): return "背包快照格式无效: \(value)"
        case .weaponNotFound(let value): return "背包中找不到武器实例: \(value)"
        case .configNotFound(let value): return "武器没有配置索引: \(value)"
        case .upgradeNotFound(let value): return "背包中找不到 Mod 实例: \(value)"
        case .gameDataNotFound(let value): return "本地游戏数据缺少条目: \(value)"
        case .unsupportedModRank(let name, let rank, let maximum):
            return "DamageKit 目前只可自动导入满级 Mod，\(name) 是 rank \(rank)/\(maximum)"
        case .unsupportedUpgrade(let value): return "未映射的武器升级: \(value)"
        case .rivenNotFound(let value): return "无法解析紫卡实例: \(value)"
        }
    }
}

/// 将 DE 背包快照中的“实例 + 配置”折成 DamageKit 的 Weapon/Build。
///
/// 静态装备从快照读取；击杀层数、战甲技能、同伴和任务状态仍由 `Options` 明确
/// 传入，因为它们不会记录在背包里。
public struct InventoryAdapter: Sendable {
    public let snapshotURL: URL
    public let gameDataURL: URL

    public init(snapshotURL: URL, gameDataURL: URL? = nil) {
        self.snapshotURL = snapshotURL
        self.gameDataURL = gameDataURL ?? Self.defaultGameDataURL(for: snapshotURL)
    }

    public static func defaultGameDataURL(for snapshotURL: URL) -> URL {
        snapshotURL.deletingLastPathComponent()       // inventory
            .deletingLastPathComponent()              // data
            .appendingPathComponent("gamedata/gamedata.json")
    }

    public func resolve(_ reference: OwnedWeaponReference, using store: DataStore) throws -> OwnedWeaponBuild {
        let snapshot = try Self.object(from: Self.readSnapshot(at: snapshotURL))
        let gameData = try Self.object(from: Self.readJSON(at: gameDataURL))
        guard let weaponObject = findWeapon(reference.weaponId, in: snapshot) else {
            throw InventoryAdapterError.weaponNotFound(reference.weaponId)
        }
        guard let itemType = Self.string(weaponObject["ItemType"]),
              let weapons = Self.objectMap(gameData["weapons"]),
              let weaponData = Self.objectMap(weapons[itemType]),
              let weaponName = Self.string(weaponData["n"]) else {
            throw InventoryAdapterError.gameDataNotFound("weapon ItemType")
        }
        let weapon = try store.weapon(named: weaponName)
        let configs = Self.array(weaponObject["Configs"])
        guard configs.indices.contains(reference.configIndex),
              let config = Self.object(configs[reference.configIndex]) else {
            throw InventoryAdapterError.configNotFound(reference.configIndex)
        }
        let slotValues = Self.array(config["Upgrades"])

        let upgrades = upgradeIndex(snapshot)
        guard let mods = Self.objectMap(gameData["mods"]) else {
            throw InventoryAdapterError.gameDataNotFound("mods")
        }
        // Current game-data builds carry Riven coefficient entries directly
        // from DE's ExportUpgrades `upgradeEntries`, which includes newer
        // completed-element terms such as Corrosive. Keep the old sidecar as
        // a compatibility fallback for an already-generated legacy cache.
        let rivenTags: [String: Any]
        if let exportedTags = Self.objectMap(gameData["rivenTags"]), !exportedTags.isEmpty {
            rivenTags = exportedTags
        } else {
            let rivenTagsURL = gameDataURL.deletingLastPathComponent()
                .appendingPathComponent("ref/riven/riven_tags.json")
            rivenTags = try Self.object(from: Self.readJSON(at: rivenTagsURL))
        }
        let disposition = Self.number(weaponData["om"]) ?? 1.2

        var names: [String] = []
        var installed: [InstalledMod] = []
        var riven: Riven?
        for (slot, rawValue) in slotValues.enumerated() {
            guard let upgradeID = rawValue as? String, !upgradeID.isEmpty else { continue }
            let upgrade: [String: Any]
            let instanceID: String
            if upgradeID.hasPrefix("/") {
                upgrade = ["ItemType": upgradeID]
                instanceID = upgradeID
            } else {
                guard let found = upgrades[upgradeID] else {
                    throw InventoryAdapterError.upgradeNotFound(upgradeID)
                }
                upgrade = found
                instanceID = upgradeID
            }
            guard let upgradeType = Self.string(upgrade["ItemType"]) else {
                throw InventoryAdapterError.unsupportedUpgrade(upgradeID)
            }
            let fingerprint = try fingerprint(upgrade)
            let rank = Int(Self.number(fingerprint?["lvl"]) ?? 0)
            if upgradeType.contains("Randomized") {
                riven = try decodeRiven(id: instanceID, fingerprint: fingerprint, type: upgradeType,
                                        disposition: disposition, tagRoot: rivenTags)
                installed.append(InstalledMod(slot: slot, instanceId: instanceID,
                                               name: riven?.name ?? "Riven", rank: rank))
                continue
            }
            if let alias = Self.upgradeAliases[upgradeType] {
                guard rank == alias.maximumRank else {
                    throw InventoryAdapterError.unsupportedModRank(name: alias.name,
                                                                   rank: rank,
                                                                   maximum: alias.maximumRank)
                }
                names.append(alias.name)
                installed.append(InstalledMod(slot: slot, instanceId: instanceID,
                                               name: alias.name, rank: rank))
                continue
            }
            guard let mod = Self.objectMap(mods[upgradeType]), let name = Self.string(mod["n"]) else {
                throw InventoryAdapterError.gameDataNotFound(upgradeType)
            }
            let maximum = Int(Self.number(mod["mx"]) ?? 0)
            guard rank == maximum else {
                throw InventoryAdapterError.unsupportedModRank(name: name, rank: rank, maximum: maximum)
            }
            names.append(name)
            installed.append(InstalledMod(slot: slot, instanceId: instanceID, name: name, rank: rank))
        }

        let progenitor = Self.progenitorElements(from: try fingerprint(weaponObject))
        return OwnedWeaponBuild(itemId: reference.weaponId, itemType: itemType,
                                configIndex: reference.configIndex, weapon: weapon,
                                build: Build(mods: names, riven: riven,
                                             progenitorElements: progenitor),
                                installedMods: installed)
    }

    // MARK: - Snapshot decoding

    private static let upgradeAliases: [String: (name: String, maximumRank: Int)] = [
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/PrimaryDamageOnKill":
            ("Primary Merciless", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/SecondaryDamageOnKill":
            ("Secondary Merciless", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/MeleeDamageOnKill":
            ("Melee Merciless", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/SecondaryDamageOnHeatProc":
            ("Cascadia Flare", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/PrimaryCritDmgAndMultishotOnColdProc":
            ("Primary Frostbite", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/PrimaryDamageOnNoMelee":
            ("Primary Deadhead", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/SecondaryDamageOnNoMelee":
            ("Secondary Deadhead", 5),
        "/Lotus/Upgrades/CosmeticEnhancers/Offensive/CorrosiveMeleePerAbilityCast":
            ("Melee Exposure", 5)
    ]

    private func findWeapon(_ id: String, in snapshot: [String: Any]) -> [String: Any]? {
        let categories = ["LongGuns", "Pistols", "Melee", "SentinelWeapons", "SpaceGuns", "SpaceMelee"]
        for category in categories {
            for raw in Self.array(snapshot[category]) {
                guard let candidate = Self.object(raw),
                      let item = Self.object(candidate["ItemId"]),
                      Self.string(item["$oid"]) == id else { continue }
                return candidate
            }
        }
        return nil
    }

    private func upgradeIndex(_ snapshot: [String: Any]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for raw in Self.array(snapshot["Upgrades"]) {
            guard let upgrade = Self.object(raw), let item = Self.object(upgrade["ItemId"]),
                  let id = Self.string(item["$oid"]) else { continue }
            result[id] = upgrade
        }
        return result
    }

    private func decodeRiven(id: String, fingerprint: [String: Any]?, type: String,
                             disposition: Double, tagRoot: [String: Any]) throws -> Riven {
        guard let fingerprint else {
            throw InventoryAdapterError.rivenNotFound(id)
        }
        let rivenType = type.split(separator: "/").last.map(String.init) ?? ""
        let rows = Self.array(tagRoot[rivenType])
        guard !rows.isEmpty else { throw InventoryAdapterError.rivenNotFound(id) }
        var byTag: [String: [String: Any]] = [:]
        for raw in rows where Self.object(raw) != nil {
            let row = Self.object(raw)!
            if let tag = Self.string(row["tag"]) { byTag[tag] = row }
        }
        let buffs = Self.array(fingerprint["buffs"])
        let curses = Self.array(fingerprint["curses"])
        let rank = Int(Self.number(fingerprint["lvl"]) ?? 0)
        let curseAttenuation = pow(1.25, Double(curses.count))

        func value(_ raw: [String: Any], curse: Bool) -> Double? {
            guard let tag = Self.string(raw["Tag"]), let row = byTag[tag],
                  let base = Self.number(row["value"]), let stored = Self.number(raw["Value"]) else { return nil }
            var result = base * 1.5 * disposition * 10 * (curse ? -1 : 1)
            if curse {
                result *= Self.rivenCurseAttenuation[min(buffs.count, 5)]
                result *= Self.rivenBuffAttenuation[min(curses.count, 5)]
            } else {
                result *= curseAttenuation
                result *= Self.rivenBuffAttenuation[min(buffs.count, 5)]
            }
            let fraction = min(max(stored / Self.rivenMaximum, 0), 1)
            result *= 0.9 + 0.2 * fraction
            result *= Double(rank + 1)
            return (result * 10_000).rounded() / 10_000
        }

        var statusDuration: Double?
        var critDamage: Double?
        var critChance: Double?
        var damage: Double?
        var multishot: Double?
        var statusChance: Double?
        var fireRate: Double?
        var reloadSpeed: Double?
        var magazineSize: Double?
        var ammoEfficiency: Double?
        var meleeComboEfficiency: Double?
        var elements: [String: Double] = [:]
        var physical: [String: Double] = [:]
        var factions: [String: Double] = [:]

        func add(_ raw: [String: Any], curse: Bool) {
            guard let tag = Self.string(raw["Tag"]), let parsed = value(raw, curse: curse) else { return }
            switch tag {
            case "WeaponProcTimeMod": statusDuration = (statusDuration ?? 0) + parsed
            case "WeaponCritDamageMod": critDamage = (critDamage ?? 0) + parsed
            case "WeaponCritChanceMod": critChance = (critChance ?? 0) + parsed
            case "WeaponDamageAmountMod", "WeaponMeleeDamageMod": damage = (damage ?? 0) + parsed
            case "WeaponFireIterationsMod": multishot = (multishot ?? 0) + parsed
            case "WeaponStunChanceMod": statusChance = (statusChance ?? 0) + parsed
            case "WeaponFireRateMod": fireRate = (fireRate ?? 0) + parsed
            case "WeaponReloadSpeedMod": reloadSpeed = (reloadSpeed ?? 0) + parsed
            case "WeaponClipMaxMod": magazineSize = (magazineSize ?? 0) + parsed
            case "WeaponAmmoEfficiency": ammoEfficiency = (ammoEfficiency ?? 0) + parsed
            case "WeaponMeleeComboEfficiencyMod": meleeComboEfficiency = (meleeComboEfficiency ?? 0) + parsed
            case "WeaponFireDamageMod", "WeaponHeatDamageMod": elements["heat", default: 0] += parsed
            case "WeaponFreezeDamageMod", "WeaponColdDamageMod": elements["cold", default: 0] += parsed
            case "WeaponElectricityDamageMod": elements["electricity", default: 0] += parsed
            case "WeaponToxinDamageMod", "WeaponPoisonDamageMod": elements["toxin", default: 0] += parsed
            // These Riven entries are completed element types in the public
            // export. They must not be expanded into primary elements and
            // re-combined according to a fabricated Mod-slot order.
            case "WeaponBlastDamageMod": elements["blast", default: 0] += parsed
            case "WeaponCorrosiveDamageMod": elements["corrosive", default: 0] += parsed
            case "WeaponGasDamageMod": elements["gas", default: 0] += parsed
            case "WeaponMagneticDamageMod": elements["magnetic", default: 0] += parsed
            case "WeaponRadiationDamageMod": elements["radiation", default: 0] += parsed
            case "WeaponViralDamageMod": elements["viral", default: 0] += parsed
            case "WeaponImpactDamageMod": physical["impact", default: 0] += parsed
            case "WeaponSlashDamageMod": physical["slash", default: 0] += parsed
            case "WeaponArmorPiercingDamageMod", "WeaponPunctureDamageMod": physical["puncture", default: 0] += parsed
            case "WeaponFactionDamageGrineer", "WeaponMeleeFactionDamageGrineer": factions["Grineer", default: 0] += parsed
            case "WeaponFactionDamageCorpus", "WeaponMeleeFactionDamageCorpus": factions["Corpus", default: 0] += parsed
            case "WeaponFactionDamageInfested", "WeaponMeleeFactionDamageInfested": factions["Infested", default: 0] += parsed
            case "WeaponFactionDamageCorrupted": factions["Orokin", default: 0] += parsed
            default: break
            }
        }
        buffs.compactMap { Self.object($0) }.forEach { add($0, curse: false) }
        curses.compactMap { Self.object($0) }.forEach { add($0, curse: true) }
        return Riven(name: Self.rivenName(buffs: buffs, tags: byTag), damage: damage,
                     multishot: multishot, critChance: critChance, critDamage: critDamage,
                     statusChance: statusChance, statusDuration: statusDuration,
                     fireRate: fireRate, reloadSpeed: reloadSpeed,
                     magazineSize: magazineSize, ammoEfficiency: ammoEfficiency,
                     meleeComboEfficiency: meleeComboEfficiency,
                     factionBonuses: factions.isEmpty ? nil : factions,
                     elements: elements.isEmpty ? nil : elements,
                     physical: physical.isEmpty ? nil : physical)
    }

    private static let rivenBuffAttenuation: [Double] = [0, 1, 0.66000003, 0.5, 0.40000001, 0.34999999]
    private static let rivenCurseAttenuation: [Double] = [0, 1, 0.33000001, 0.5, 1.25, 1.5]
    private static let rivenMaximum = 1_073_741_823.0

    private static func rivenName(buffs: [Any], tags: [String: [String: Any]]) -> String {
        let sorted = buffs.compactMap { Self.object($0) }.sorted {
            (Self.number($0["Value"]) ?? 0) > (Self.number($1["Value"]) ?? 0)
        }
        var name = ""
        for (index, buff) in sorted.enumerated() {
            guard let tag = Self.string(buff["Tag"]), let row = tags[tag] else { continue }
            if index == sorted.count - 1 {
                name += Self.string(row["suffix"]) ?? ""
            } else if index == 0 {
                let prefix = Self.string(row["prefix"]) ?? ""
                name += prefix.prefix(1).uppercased() + String(prefix.dropFirst())
            } else {
                name += "-" + (Self.string(row["prefix"]) ?? "")
            }
        }
        return name.isEmpty ? "Riven" : name
    }

    private static func progenitorElements(from fingerprint: [String: Any]?) -> [String: Double] {
        guard let fingerprint else { return [:] }
        let names: [String: String] = [
            "InnateFireDamage": "heat",
            "InnateHeatDamage": "heat",
            "InnateFreezeDamage": "cold",
            "InnateColdDamage": "cold",
            "InnateElectricityDamage": "electricity",
            "InnateToxinDamage": "toxin",
            "InnatePoisonDamage": "toxin",
            "InnateMagDamage": "magnetic"
        ]
        var result: [String: Double] = [:]
        for raw in Self.array(fingerprint["buffs"]) {
            guard let buff = Self.object(raw), let tag = Self.string(buff["Tag"]),
                  let element = names[tag], let rawValue = Self.number(buff["Value"]) else { continue }
            result[element, default: 0] += 0.25 + 0.35 * min(max(rawValue / rivenMaximum, 0), 1)
        }
        return result
    }

    private func fingerprint(_ object: [String: Any]) throws -> [String: Any]? {
        guard let raw = Self.string(object["UpgradeFingerprint"]), !raw.isEmpty else { return nil }
        return try InventoryAdapter.object(from: Data(raw.utf8))
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InventoryAdapterError.malformedSnapshot("根节点不是对象")
        }
        return result
    }

    private static func readJSON(at url: URL) throws -> Data {
        do { return try Data(contentsOf: url) }
        catch { throw InventoryAdapterError.unreadableSnapshot(url.path) }
    }

    private static func readSnapshot(at url: URL) throws -> Data {
        if url.pathExtension.lowercased() != "gz" { return try readJSON(at: url) }
        #if os(Windows)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
        task.arguments = ["-NoProfile", "-NonInteractive", "-Command", """
            $ErrorActionPreference = 'Stop'
            $stream = [System.IO.File]::OpenRead($env:DAMAGEKIT_INVENTORY_GZIP)
            try {
              $gzip = [System.IO.Compression.GZipStream]::new($stream, [System.IO.Compression.CompressionMode]::Decompress)
              try { $gzip.CopyTo([System.Console]::OpenStandardOutput()) } finally { $gzip.Dispose() }
            } finally { $stream.Dispose() }
            """]
        var environment = ProcessInfo.processInfo.environment
        environment["DAMAGEKIT_INVENTORY_GZIP"] = url.path
        task.environment = environment
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        do { try task.run() }
        catch { throw InventoryAdapterError.unreadableSnapshot(url.path) }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw InventoryAdapterError.unreadableSnapshot(url.path)
        }
        return data
        #else
        throw InventoryAdapterError.unreadableSnapshot(".gz 快照需要在支持 GZip 的宿主上解压: \(url.path)")
        #endif
    }

    private static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func objectMap(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func array(_ value: Any?) -> [Any] { value as? [Any] ?? [] }
    private static func string(_ value: Any?) -> String? { value as? String }
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }
}
