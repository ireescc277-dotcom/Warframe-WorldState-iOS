import Foundation
import DamageKit

/// Whether a weapon-affecting ability can be applied only by the equipped
/// Warframe, or can also arrive from a squadmate.  This is source capability,
/// not an arbitrary placement chosen by the UI.
enum WarframeBuffAudience: Hashable {
    case selfOnly
    case selfAndAllies
}

/// One concrete weapon-affecting skill made available by an owned Warframe
/// configuration.  The candidate stores no free-form final value: the value
/// is resolved from the caster's actual Mod/shard configuration at use time.
struct WarframeWeaponBuffCandidate: Identifiable, Hashable {
    enum Route: Hashable {
        /// The damage engine already owns this ability's special damage path.
        /// The two base coefficients distinguish a native cast from a
        /// Helminth-injected cast where DE specifies diminished effectiveness.
        case scenario(effect: ScenarioEffectID, nativeBase: Double, helminthBase: Double?)
        /// A rank-scaled ability augment whose action is represented in
        /// DamageKit's Mod table.
        case externalMod(modName: String, rankScale: Double)
    }

    let id: String
    let name: String
    let detail: String
    let sourceAbilityName: String
    /// Game slot of the ability cast, one-based.  This lets Precision
    /// Intensify apply only when the actual fourth ability is being used.
    let abilityOrdinal: Int
    let isHelminth: Bool
    let audience: WarframeBuffAudience
    let route: Route

    var canBuffAllies: Bool { audience == .selfAndAllies }
}

/// A candidate together with the fully resolved caster-specific result.
struct WarframeWeaponBuffResolution {
    let candidate: WarframeWeaponBuffCandidate
    let strength: WarframeStrengthResolution
    let scenarioEffect: (effect: ScenarioEffectID, value: Double)?
    let externalSource: ExternalEffectSource?

    var finalPercent: Double? {
        guard let scenarioEffect else { return nil }
        return scenarioEffect.value * 100
    }
}

/// Maps abilities and equipped augment cards to the pre-existing DamageKit
/// routes.  This file deliberately contains only effects whose base value and
/// damage placement have both been checked; it does not turn every equipped
/// Warframe mod into a generic buff picker.
enum WarframeWeaponBuffResolver {
    private struct AbilitySource: Hashable {
        let name: String
        let ordinal: Int
        let isHelminth: Bool
    }

    static func candidates(for warframe: InventoryData.OwnedWarframe,
                           configIndex: Int,
                           audience requestedAudience: WarframeBuffAudience) -> [WarframeWeaponBuffCandidate] {
        guard let config = warframe.config(at: configIndex) else { return [] }

        let replacedNativeIndex = config.helminth?.replacedIndex
        var abilities = warframe.abilities
            .filter { ability in ability.ordinal - 1 != replacedNativeIndex }
            .map { AbilitySource(name: $0.name, ordinal: $0.ordinal, isHelminth: false) }

        if let helminth = config.helminth {
            abilities.append(AbilitySource(
                name: helminth.name,
                ordinal: (helminth.replacedIndex ?? -1) + 1,
                isHelminth: true
            ))
        }

        var result: [WarframeWeaponBuffCandidate] = []
        for ability in abilities {
            if let candidate = abilityCandidate(ability, config: config),
               requestedAudience == .selfOnly || candidate.canBuffAllies {
                result.append(candidate)
            }
        }

        // These two are augment buffs, not standalone Mod effects.  An
        // equipped card plus its underlying ability must both be present.  The
        // exporter supplies its exact rank coefficient from the local static
        // data, so a rank-0 card cannot become a max-rank 100% buff here.
        if let shock = ability(namedOneOf: ["shock", "电击"], in: abilities),
           let upgrade = config.upgrades.first(where: { sameName($0.name, "Shock Trooper") }),
           let rankScale = upgrade.weaponBuffScale {
            result.append(.init(
                id: "mod-shock-trooper",
                name: "电击战士",
                detail: "\(upgrade.name) 等级 \(upgrade.rankLabel)；按施放者技能强度结算电击附伤",
                sourceAbilityName: shock.name,
                abilityOrdinal: shock.ordinal,
                isHelminth: shock.isHelminth,
                audience: .selfAndAllies,
                route: .externalMod(modName: "Shock Trooper", rankScale: rankScale)
            ))
        }

        if let spores = ability(namedOneOf: ["spores", "孢子"], in: abilities),
           let upgrade = config.upgrades.first(where: { sameName($0.name, "Venom Dose") }),
           let rankScale = upgrade.weaponBuffScale {
            result.append(.init(
                id: "mod-venom-dose",
                name: "毒液注入",
                detail: "\(upgrade.name) 等级 \(upgrade.rankLabel)；按施放者技能强度结算腐蚀附伤",
                sourceAbilityName: spores.name,
                abilityOrdinal: spores.ordinal,
                isHelminth: spores.isHelminth,
                audience: .selfAndAllies,
                route: .externalMod(modName: "Venom Dose", rankScale: rankScale)
            ))
        }

        return result
            .filter { requestedAudience == .selfOnly || $0.canBuffAllies }
            .sorted { lhs, rhs in lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
    }

    static func resolve(_ candidate: WarframeWeaponBuffCandidate,
                        caster: InventoryData.OwnedWarframe,
                        configIndex: Int) -> WarframeWeaponBuffResolution {
        let strength = WarframeStrengthResolver.resolve(
            caster,
            configIndex: configIndex,
            abilityOrdinal: candidate.abilityOrdinal > 0 ? candidate.abilityOrdinal : nil
        )

        switch candidate.route {
        case let .scenario(effect, nativeBase, helminthBase):
            let base = candidate.isHelminth ? (helminthBase ?? nativeBase) : nativeBase
            return .init(
                candidate: candidate,
                strength: strength,
                scenarioEffect: (effect, max(0, base * strength.multiplier)),
                externalSource: nil
            )
        case let .externalMod(modName, rankScale):
            return .init(
                candidate: candidate,
                strength: strength,
                scenarioEffect: nil,
                externalSource: ExternalEffectSource(
                    name: "\(caster.z) · \(configLabel(caster, configIndex)) · \(candidate.name)",
                    mod: modName,
                    active: true,
                    abilityStrength: strength.multiplier,
                    effectScale: rankScale
                )
            )
        }
    }

    private static func abilityCandidate(
        _ ability: AbilitySource,
        config: InventoryData.OwnedWarframe.Config
    ) -> WarframeWeaponBuffCandidate? {
        let key = canonical(ability.name)
        switch key {
        case "roar", "咆哮":
            // Native rank-3 +50%; Helminth rank-3 +30%.
            // https://wiki.warframe.com/w/Roar
            return scenario(
                id: "scenario-roar",
                name: "咆哮",
                detail: "对自身和小队成员的派系伤害加成",
                ability: ability,
                audience: .selfAndAllies,
                effect: .roar,
                nativeBase: 0.50,
                helminthBase: 0.30
            )
        case "eclipse", "日蚀", "黯然失色":
            // Solar Eclipse native rank-3 +200%; Helminth rank-3 +30%.
            // https://wiki.warframe.com/w/Eclipse
            let hasTotalEclipse = config.upgrades.contains { sameName($0.name, "Total Eclipse") }
            return scenario(
                id: "scenario-eclipse",
                name: "日蚀",
                detail: hasTotalEclipse
                    ? "Solar Eclipse；已装备 Total Eclipse，可施加给队友"
                    : "Solar Eclipse；仅对施放者自身生效（未装备 Total Eclipse）",
                ability: ability,
                audience: hasTotalEclipse ? .selfAndAllies : .selfOnly,
                effect: .eclipse,
                nativeBase: 2.00,
                helminthBase: 0.30
            )
        case "nourish", "滋养", "消化滋养":
            // Native rank-3 +75% Viral; Helminth rank-3 +45%.
            // https://wiki.warframe.com/w/Nourish
            return scenario(
                id: "scenario-nourish",
                name: "滋养",
                detail: "对自身和小队成员追加 Viral 武器伤害",
                ability: ability,
                audience: .selfAndAllies,
                effect: .nourish,
                nativeBase: 0.75,
                helminthBase: 0.45
            )
        case "xataswhisper", "xata", "虚空低语", "真理密语":
            // Rank-3 Xata's Whisper adds 26% of total weapon damage as an
            // independent Void hit. https://wiki.warframe.com/w/Xata%27s_Whisper
            return scenario(
                id: "scenario-xata",
                name: "虚空低语",
                detail: "仅施放者：每次命中增加独立 Void 伤害",
                ability: ability,
                audience: .selfOnly,
                effect: .xata,
                nativeBase: 0.26,
                helminthBase: nil
            )
        case "toxiclash", "毒鞭", "剧毒鞭笞":
            // Toxic Lash is Saryn's native ability and is not a transferable
            // squad buff.  A Helminth source with this name would be invalid,
            // so do not invent one from a malformed snapshot.
            // Rank-3 gun coefficient is 30% (melee doubling is in DamageKit).
            // https://wiki.warframe.com/w/Toxic_Lash
            guard !ability.isHelminth else { return nil }
            return scenario(
                id: "scenario-toxic-lash",
                name: "毒鞭",
                detail: "仅施放者：独立 Toxin 命中与持续伤害；近战系数由 DamageKit 处理",
                ability: ability,
                audience: .selfOnly,
                effect: .toxicLash,
                nativeBase: 0.30,
                helminthBase: nil
            )
        default:
            return nil
        }
    }

    private static func scenario(
        id: String,
        name: String,
        detail: String,
        ability: AbilitySource,
        audience: WarframeBuffAudience,
        effect: ScenarioEffectID,
        nativeBase: Double,
        helminthBase: Double?
    ) -> WarframeWeaponBuffCandidate {
        .init(
            id: id,
            name: name,
            detail: detail,
            sourceAbilityName: ability.name,
            abilityOrdinal: ability.ordinal,
            isHelminth: ability.isHelminth,
            audience: audience,
            route: .scenario(effect: effect, nativeBase: nativeBase, helminthBase: helminthBase)
        )
    }

    private static func ability(namedOneOf names: [String], in sources: [AbilitySource]) -> AbilitySource? {
        let desired = Set(names.map(canonical))
        return sources.first { desired.contains(canonical($0.name)) }
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    private static func canonical(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber || $0.unicodeScalars.contains { $0.value > 0x7f } }
    }

    private static func configLabel(_ caster: InventoryData.OwnedWarframe, _ configIndex: Int) -> String {
        caster.config(at: configIndex)?.label ?? "配置 \(configIndex + 1)"
    }
}
