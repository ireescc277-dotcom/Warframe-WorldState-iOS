import Foundation

/// A data-driven default melee sequence.  The weapon data identifies a stance
/// family through `compTags` (for example `SWORDS_STANCE`); this sequence turns
/// that family into the hits emitted by one ordinary combo cycle.
///
/// The values mirror the local warframe-damage fallback table, but the
/// simulator owns their consumption.  No view needs to know how a melee combo
/// changes hit cadence, damage, or forced statuses.
public struct MeleeAttackSequence: Sendable, Equatable {
    /// Duration of one unmodded combo cycle in seconds.
    public var cycleDuration: Double
    /// Damage multiplier applied to each hit in cycle order.
    public var hitMultipliers: [Double]
    /// Extra status applied by the corresponding hit, if any.
    public var forcedStatuses: [String]
    /// Heavy attacks include the weapon's wind-up after their source-data
    /// combo duration. Normal stance contacts leave this at zero.
    public var windUp: Double

    public init(cycleDuration: Double, hitMultipliers: [Double],
                forcedStatuses: [String] = [], windUp: Double = 0) {
        self.cycleDuration = cycleDuration
        self.hitMultipliers = hitMultipliers
        self.forcedStatuses = forcedStatuses
        self.windUp = windUp
    }

    public var normalizedStatuses: [String] {
        if forcedStatuses.count == hitMultipliers.count { return forcedStatuses }
        return Array(repeating: "", count: hitMultipliers.count)
    }
}

/// A selectable normal combo supplied by an equipped stance Mod.  The name is
/// the same value the website keeps in its stance-combo selector; the sequence
/// is parsed from that Mod's `action.stances` data rather than maintained in a
/// second, weapon-specific formula table.
public struct MeleeStanceCombo: Sendable, Equatable {
    public var name: String
    public var sequence: MeleeAttackSequence

    public init(name: String, sequence: MeleeAttackSequence) {
        self.name = name
        self.sequence = sequence
    }
}

/// Default normal-combo timing where no stance Mod is fitted.  This is kept as
/// structured Swift data so DamageKit remains pure Swift at runtime: it never
/// invokes the JavaScript website or parses a browser bundle.
public enum MeleeStanceLibrary {
    private static func sequence(_ duration: Double, _ hits: [Double],
                                 _ statuses: [String] = []) -> MeleeAttackSequence {
        .init(cycleDuration: duration, hitMultipliers: hits, forcedStatuses: statuses)
    }

    /// Literal data exported from the local website source.  A record may
    /// contain a normal combo, a heavy combo, or both (weapon-specific heavy
    /// overrides such as Quassus intentionally contain only `heavy`).
    private struct DefaultSequenceRecord: Decodable {
        var total: FlexibleNumber?
        var hits: [FlexibleNumber]?
        var statuses: [String]?

        var sequence: MeleeAttackSequence? {
            guard let duration = total?.doubleValue,
                  let rawHits = hits else { return nil }
            let multipliers = rawHits.compactMap(\.doubleValue)
            guard !multipliers.isEmpty else { return nil }
            return MeleeStanceLibrary.sequence(duration, multipliers, statuses ?? [])
        }
    }

    private struct DefaultStanceRecord: Decodable {
        var total: FlexibleNumber?
        var hits: [FlexibleNumber]?
        var statuses: [String]?
        var heavy: DefaultSequenceRecord?

        var sequence: MeleeAttackSequence? {
            DefaultSequenceRecord(total: total, hits: hits, statuses: statuses).sequence
        }
    }

    private static let defaultStanceRecords: [String: DefaultStanceRecord] = {
        guard let url = Bundle.module.url(forResource: "default-melee-stances",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: DefaultStanceRecord].self, from: data)
        else {
            return [:]
        }
        // Website lookup uses the weapon name first and then the first
        // compatibility tag.  Normalize the key without changing that order.
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.key.uppercased(), $0.value) })
    }()

    /// Parses selectable normal combos from a stance Mod's raw data.  The
    /// website stores the same values under `action.stances`; the simulator
    /// receives only this parsed data and has no stance-name formula branches.
    public static func combos(in stanceMod: ModDefinition,
                              orderedNames: [String] = []) -> [MeleeStanceCombo] {
        guard stanceMod.type?.caseInsensitiveCompare("stance") == .orderedSame,
              let rawCombos = stanceMod.action?["stances"]?.objectValue else {
            return []
        }

        let parsed = rawCombos.compactMap { name, raw -> MeleeStanceCombo? in
            guard let definition = raw.objectValue,
                  let duration = definition["total"]?.doubleValue,
                  let hits = definition["hits"]?.arrayValue?.compactMap(\.doubleValue),
                  !hits.isEmpty else {
                return nil
            }
            let statuses = definition["statuses"]?.arrayValue?.map { $0.stringValue ?? "" } ?? []
            return MeleeStanceCombo(
                name: name,
                sequence: sequence(duration, hits, statuses)
            )
        }
        guard !orderedNames.isEmpty else {
            // Callers with raw third-party Mod data have no exported order.
            // Keep that fallback deterministic rather than depending on a
            // dictionary iteration order that changes across processes.
            return parsed.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        let byName = Dictionary(uniqueKeysWithValues: parsed.map { ($0.name, $0) })
        let expected = orderedNames.compactMap { byName[$0] }
        let known = Set(expected.map(\.name))
        let newUnindexed = parsed
            .filter { !known.contains($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return expected + newUnindexed
    }

    /// Returns the normal-combo sequence for a melee normal attack.  A fitted
    /// stance takes precedence over the built-in fallback.  If an old saved
    /// build did not record a combo name, choose the first source-data option,
    /// matching the website's initial dropdown selection.
    public static func sequence(for weapon: Weapon, attack: Attack,
                                stanceMod: ModDefinition?, comboName: String?,
                                orderedNames: [String] = [],
                                heavy: Bool = false) -> MeleeAttackSequence? {
        guard isMelee(weapon) else { return nil }
        let useHeavy = heavy || attack.isHeavy
        if useHeavy {
            // The website deliberately ignores the equipped stance Mod for a
            // heavy attack and pulls the default heavy family / weapon record.
            // Slam variants then overwrite that pattern with exactly one hit.
            if isSlamAttack(attack) {
                return .init(cycleDuration: 1, hitMultipliers: [1])
            }
            guard var sequence = defaultSequence(for: weapon, attack: attack, heavy: true) else {
                return nil
            }
            sequence.windUp = max(0, weapon.windUp ?? 0)
            return sequence
        }
        guard isOrdinaryAttack(attack) else { return nil }
        if let stanceMod {
            let choices = combos(in: stanceMod, orderedNames: orderedNames)
            if let comboName,
               let choice = choices.first(where: {
                   $0.name.caseInsensitiveCompare(comboName) == .orderedSame
               }) {
                return choice.sequence
            }
            if let choice = choices.first { return choice.sequence }
        }
        return defaultSequence(for: weapon, attack: attack)
    }

    /// Returns the default normal-combo sequence for a melee normal attack.
    /// Slam and explicitly named heavy attacks have their own attack data and
    /// intentionally do not borrow a normal-combo cadence.
    public static func defaultSequence(for weapon: Weapon, attack: Attack,
                                       heavy: Bool = false) -> MeleeAttackSequence? {
        guard isMelee(weapon), heavy || isOrdinaryAttack(attack) else { return nil }
        // The website consults a per-weapon override, then its first compTag.
        // A later compatibility tag must not silently select a different
        // cadence than the website would use.
        let keys = [weapon.name] + (weapon.compTags?.first.map { [$0] } ?? [])
        for key in keys {
            guard let record = defaultStanceRecords[key.uppercased()] else { continue }
            if heavy, let sequence = record.heavy?.sequence { return sequence }
            if !heavy, let sequence = record.sequence { return sequence }
        }
        return nil
    }

    private static func isMelee(_ weapon: Weapon) -> Bool {
        if weapon.category?.caseInsensitiveCompare("Melee") == .orderedSame { return true }
        return (weapon.categories ?? []).contains {
            $0.caseInsensitiveCompare("melee") == .orderedSame
        }
    }

    private static func isOrdinaryAttack(_ attack: Attack) -> Bool {
        let rawType = attack.attackType?.lowercased()
        if rawType == "h" || rawType == "s" || rawType == "hs" { return false }
        let name = attack.name.lowercased()
        return !name.contains("slam") && !name.contains("heavy") && !name.contains("slide")
    }

    private static func isSlamAttack(_ attack: Attack) -> Bool {
        let rawType = attack.attackType?.lowercased()
        return rawType == "s" || rawType == "hs"
    }
}
