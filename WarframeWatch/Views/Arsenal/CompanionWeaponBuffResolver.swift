import Foundation

/// One weapon-affecting Mod found in a concrete companion's imported A/B/C
/// configuration.  This is deliberately a small, source-bound list rather
/// than a generic picker: a companion Mod only reaches the calculator when
/// the selected account instance actually has that card equipped.
struct CompanionWeaponBuffCandidate: Identifiable, Hashable {
    enum Activation: Hashable {
        /// The card's gameplay trigger is represented by the on/off control.
        /// DamageKit has no numeric `WITH_COND` action for this entry.
        case trigger
        /// DamageKit's action has a numeric `WITH_COND` branch.  The player
        /// must explicitly say how much of that condition is true now.
        case conditionValue
    }

    /// DamageKit's compact Mod action is stored at the card's maximum rank.
    /// Do not infer a lower-rank curve from just `rank / maxRank`.
    enum Availability: Hashable {
        case ready
        case rankUnknown
        case maximumUnknown(rank: Int)
        case notMaximum(rank: Int, maximum: Int)
        case invalidRank(rank: Int, maximum: Int)

        var canCalculate: Bool {
            if case .ready = self { return true }
            return false
        }

        var detail: String {
            switch self {
            case .ready:
                return "已按实际配置导入；启用后会写入本次伤害计算。"
            case .rankUnknown:
                return "此卡等级未能从账号快照确认；不会按满级结算。"
            case let .maximumUnknown(rank):
                return "已读到等级 \(rank)，但没有可靠的最高等级；不会猜测效果。"
            case let .notMaximum(rank, maximum):
                return "实际等级 \(rank)/\(maximum)。当前 DamageKit 条目只保存满级作用值，未证明低等级曲线，因此不结算。"
            case let .invalidRank(rank, maximum):
                return "快照给出异常等级 \(rank)/\(maximum)；不会结算。"
            }
        }
    }

    let id: String
    let companionID: String
    let companionName: String
    let configurationLabel: String
    let slot: Int
    /// Exact DamageKit table key.  The display name stays separate so this is
    /// not a UI-label-to-formula guess.
    let modName: String
    let importedName: String
    let rankLabel: String
    let activation: Activation
    let availability: Availability

    var canCalculate: Bool { availability.canCalculate }
    var requiresConditionValue: Bool { activation == .conditionValue }
}

/// Maps only companion Mods whose DamageKit action and source ownership have
/// both been audited.  The list is intentionally explicit: an arbitrary Mod
/// in a pet's configuration is not evidence that it modifies the player's
/// weapon.
enum CompanionWeaponBuffResolver {
    private struct Spec: Hashable {
        let modName: String
        let activation: CompanionWeaponBuffCandidate.Activation
    }

    private static let specs: [Spec] = [
        .init(modName: "Mecha Empowered", activation: .trigger),
        .init(modName: "Tek Collateral", activation: .conditionValue),
        .init(modName: "Reinforced Bond", activation: .conditionValue),
        .init(modName: "Tenacious Bond", activation: .conditionValue),
    ]

    private static let specsByName = Dictionary(
        uniqueKeysWithValues: specs.map {
            (CompanionWeaponBuffResolver.canonical($0.modName), $0)
        }
    )

    static func candidates(for companion: InventoryData.OwnedEquipment,
                           configIndex: Int) -> [CompanionWeaponBuffCandidate] {
        guard let config = companion.config(at: configIndex) else { return [] }
        return config.upgrades.compactMap { upgrade in
            guard upgrade.kind.caseInsensitiveCompare("Mod") == .orderedSame,
                  let spec = specsByName[canonical(upgrade.name)]
            else { return nil }

            let availability = availability(rank: upgrade.rank, maximum: upgrade.maxRank)
            return CompanionWeaponBuffCandidate(
                id: "\(companion.id)|\(config.label)|\(upgrade.slot)|\(spec.modName)",
                companionID: companion.id,
                companionName: companion.z,
                configurationLabel: config.label,
                slot: upgrade.slot,
                modName: spec.modName,
                importedName: upgrade.name,
                rankLabel: upgrade.rankLabel,
                activation: spec.activation,
                availability: availability
            )
        }
        .sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return lhs.modName.localizedStandardCompare(rhs.modName) == .orderedAscending
        }
    }

    private static func availability(rank: Int?, maximum: Int?) -> CompanionWeaponBuffCandidate.Availability {
        guard let rank, rank >= 0 else { return .rankUnknown }
        guard let maximum, maximum >= 0 else { return .maximumUnknown(rank: rank) }
        guard rank <= maximum else { return .invalidRank(rank: rank, maximum: maximum) }
        return rank == maximum
            ? .ready
            : .notMaximum(rank: rank, maximum: maximum)
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
