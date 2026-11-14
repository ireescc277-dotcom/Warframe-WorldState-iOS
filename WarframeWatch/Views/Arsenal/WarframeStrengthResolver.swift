import Foundation

/// Resolves Ability Strength from a concrete Warframe configuration.
///
/// This intentionally has no free-form percentage input.  The only inputs are
/// the exported card ranks, the shards installed on that Warframe, and the
/// selected ability ordinal.  Conditional sources are kept separate so a
/// build never receives a full-stack/triggered bonus merely because the card
/// happens to be equipped.
struct WarframeStrengthResolution: Equatable {
    struct Contribution: Identifiable, Equatable {
        let id: String
        let label: String
        /// Decimal addition to the base 1.0 multiplier.
        let value: Double
    }

    let multiplier: Double
    let contributions: [Contribution]
    /// Exact source text that is deliberately not active by default.  These
    /// will become game-state controls (stacks / next-cast / triggering buff),
    /// not another manually entered final Ability Strength field.
    let inactiveConditionalTerms: [String]
    let importIssues: [String]

    var percent: Int { Int((multiplier * 100).rounded()) }
    var isExactImport: Bool { importIssues.isEmpty }
}

enum WarframeStrengthResolver {
    /// Resolve one ability cast.  `abilityOrdinal` is deliberately optional:
    /// when no ability has been selected, e.g. a weapon-only scenario, a
    /// fourth-ability-only source such as Precision Intensify is not silently
    /// applied.
    static func resolve(_ warframe: InventoryData.OwnedWarframe,
                        configIndex: Int,
                        abilityOrdinal: Int? = nil) -> WarframeStrengthResolution {
        guard let config = warframe.config(at: configIndex) else {
            return WarframeStrengthResolution(
                multiplier: 1,
                contributions: [],
                inactiveConditionalTerms: [],
                importIssues: ["未找到 \(warframe.z) 的该配置；按 100% 技能强度计算"]
            )
        }

        var contributions: [WarframeStrengthResolution.Contribution] = []
        var conditionals: [String] = []

        for upgrade in config.upgrades {
            for term in upgrade.strengthTerms {
                let applies: Bool
                switch term.kind {
                case "base":
                    applies = true
                case "ability4":
                    applies = abilityOrdinal == 4
                default:
                    // Unknown exporter types are never treated as an always-on
                    // strength bonus.  Keeping them in the config is useful,
                    // but applying them here would be a formula guess.
                    applies = false
                }
                guard applies else { continue }
                contributions.append(.init(
                    id: "upgrade-\(upgrade.slot)-\(term.id)",
                    label: "\(upgrade.name)：\(term.label)",
                    value: term.value
                ))
            }
            for term in upgrade.strengthReview {
                conditionals.append("\(upgrade.name)：\(term)")
            }
        }

        for shard in warframe.shards {
            guard let value = shard.abilityStrength else { continue }
            contributions.append(.init(
                id: "shard-\(shard.slot)",
                label: shard.name,
                value: value
            ))
        }

        applyUmbralSetBonus(to: &contributions, upgrades: config.upgrades)

        let multiplier = max(0, 1 + contributions.reduce(0) { $0 + $1.value })
        return WarframeStrengthResolution(
            multiplier: multiplier,
            contributions: contributions,
            inactiveConditionalTerms: Array(Set(conditionals)).sorted(),
            importIssues: config.issues
        )
    }

    /// Umbral Intensify's listed strength is the level-1 set value.  The
    /// documented set table multiplies that primary value by 1.25 with two
    /// Umbral cards and by 1.75 with all three.  We add only the difference,
    /// because the base term is already present in `strengthTerms`.
    /// Source: https://wiki.warframe.com/w/Set_Mod#Umbral_Set
    private static func applyUmbralSetBonus(
        to contributions: inout [WarframeStrengthResolution.Contribution],
        upgrades: [InventoryData.OwnedWarframe.Upgrade]
    ) {
        let umbralNames: Set<String> = ["Umbral Vitality", "Umbral Fiber", "Umbral Intensify"]
        let equippedNames = Set(upgrades.map(\.name)).intersection(umbralNames)
        let level = equippedNames.count
        guard level >= 2,
              let intensify = upgrades.first(where: { $0.name == "Umbral Intensify" })
        else { return }

        let setMultiplier: Double = level == 2 ? 1.25 : 1.75
        let baseStrength = intensify.strengthTerms
            .filter { $0.kind == "base" }
            .reduce(0) { $0 + $1.value }
        guard baseStrength != 0 else { return }
        let additional = baseStrength * (setMultiplier - 1)
        contributions.append(.init(
            id: "umbral-set-\(intensify.slot)-\(level)",
            label: "Umbral 套装（\(level) 件）",
            value: additional
        ))
    }
}
