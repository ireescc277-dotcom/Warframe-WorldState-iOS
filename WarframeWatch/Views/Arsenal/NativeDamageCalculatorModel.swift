import Combine
import Dispatch
import Foundation
import DamageKit

enum NativeEffectGroup: String, CaseIterable, Identifiable {
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .environment: return "外部环境"
        }
    }
}

/// A presentation record for one core-owned website environment effect.  The
/// fields here are selection state and display units only; `ScenarioEffectID`
/// is passed untouched to DamageKit, where the formula pool is resolved.
struct NativeScenarioEffectDraft: Identifiable, Hashable {
    let effect: ScenarioEffectID
    var enabled: Bool
    var percent: Double

    var id: ScenarioEffectID { effect }

    init(effect: ScenarioEffectID, enabled: Bool = false, percent: Double? = nil) {
        self.effect = effect
        self.enabled = enabled
        self.percent = percent ?? effect.defaultDisplayValue
    }
}

/// One externally cast Warframe weapon buff.  It identifies the caster and
/// that caster's A/B/C configuration; it deliberately has no strength field.
/// The selected ability is resolved against the source configuration every
/// time the calculator runs.
struct NativeExternalWarframeBuffDraft: Identifiable, Hashable {
    let id: UUID
    var casterID: String?
    var configIndex: Int
    var candidateID: String?
    var active: Bool

    init(casterID: String? = nil, configIndex: Int = 0,
         candidateID: String? = nil, active: Bool = true) {
        id = UUID()
        self.casterID = casterID
        self.configIndex = configIndex
        self.candidateID = candidateID
        self.active = active
    }
}

/// A deliberately explicit manual source for any buff that is not in the Mod
/// catalogue.  This is an input contract, not a hidden named special case.
struct NativeManualBuffDraft: Identifiable, Hashable {
    let id: UUID
    var name: String = "自定义环境 Buff"
    var active: Bool = true
    /// Values are decimal bonuses: 0.30 means +30%.
    var damageBonus: Double = 0
    var critChanceBonus: Double = 0
    var critDamageBonus: Double = 0
    var multishotBonus: Double = 0
    var fireRateBonus: Double = 0
    var reloadSpeedBonus: Double = 0
    var statusChanceBonus: Double = 0
    var statusDurationBonus: Double = 0
    var statusDamageBonus: Double = 0
    var factionBonus: Double = 0
    /// Extra direct elemental damage, relative to the weapon's unmodded base
    /// damage.  These are separate from the weapon-Mod element merge.
    var heatElementBonus: Double = 0
    var coldElementBonus: Double = 0
    var electricityElementBonus: Double = 0
    var toxinElementBonus: Double = 0
    /// Damage bonuses for already-created damaging status effects.
    var heatStatusDamageBonus: Double = 0
    var electricityStatusDamageBonus: Double = 0
    var toxinStatusDamageBonus: Double = 0

    private func nonZero(_ value: Double) -> Double? {
        abs(value) > .ulpOfOne ? value : nil
    }

    private var elements: [String: Double] {
        [
            "heat": heatElementBonus,
            "cold": coldElementBonus,
            "electricity": electricityElementBonus,
            "toxin": toxinElementBonus,
        ].compactMapValues(nonZero)
    }

    private var statusElementBonuses: [String: Double] {
        [
            "heat": heatStatusDamageBonus,
            "electricity": electricityStatusDamageBonus,
            "toxin": toxinStatusDamageBonus,
        ].compactMapValues(nonZero)
    }

    func source() -> ExternalEffectSource {
        let buff = ExternalWeaponBuff(
            damageBonus: damageBonus,
            critChanceBonus: critChanceBonus,
            critDamageBonus: critDamageBonus,
            multishotBonus: multishotBonus,
            fireRateBonus: fireRateBonus,
            reloadSpeedBonus: reloadSpeedBonus,
            statusChanceBonus: statusChanceBonus,
            statusDurationBonus: statusDurationBonus,
            statusDamageBonus: statusDamageBonus,
            factionBonus: factionBonus,
            elements: elements,
            statusElementBonuses: statusElementBonuses
        )
        return ExternalEffectSource(name: name, active: active, buff: buff)
    }
}

/// A real Riven rolls a short list of named effects.  Keeping that list as
/// explicit rows prevents the UI from looking like a generic weapon-stat panel
/// and lets an imported card be checked term by term.
enum NativeRivenStatGroup: String, CaseIterable, Identifiable {
    case core
    case status
    case element
    case physical
    case faction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: return "基础词条"
        case .status: return "暴击与状态"
        case .element: return "元素伤害"
        case .physical: return "物理伤害"
        case .faction: return "阵营伤害"
        }
    }
}

enum NativeRivenStat: String, CaseIterable, Identifiable, Hashable {
    case damage, multishot, critChance, critDamage, fireRate, reloadSpeed
    case statusChance, statusDuration
    case heat, cold, electricity, toxin
    case impact, puncture, slash
    case grineerFaction, corpusFaction, infestedFaction, orokinFaction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .damage: return "基础伤害"
        case .multishot: return "多重射击"
        case .critChance: return "暴击率"
        case .critDamage: return "暴击伤害"
        case .fireRate: return "射速 / 攻速"
        case .reloadSpeed: return "装填速度"
        case .statusChance: return "触发几率"
        case .statusDuration: return "状态持续时间"
        case .heat: return "火焰伤害"
        case .cold: return "冰冻伤害"
        case .electricity: return "电击伤害"
        case .toxin: return "毒素伤害"
        case .impact: return "冲击伤害"
        case .puncture: return "穿刺伤害"
        case .slash: return "切割伤害"
        case .grineerFaction: return "对 Grineer 伤害"
        case .corpusFaction: return "对 Corpus 伤害"
        case .infestedFaction: return "对 Infested 伤害"
        case .orokinFaction: return "对 Corrupted 伤害"
        }
    }

    var group: NativeRivenStatGroup {
        switch self {
        case .damage, .multishot, .fireRate, .reloadSpeed:
            return .core
        case .critChance, .critDamage, .statusChance, .statusDuration:
            return .status
        case .heat, .cold, .electricity, .toxin:
            return .element
        case .impact, .puncture, .slash:
            return .physical
        case .grineerFaction, .corpusFaction, .infestedFaction, .orokinFaction:
            return .faction
        }
    }
}

/// Manual Riven fields use user-facing percentage units.  DamageKit receives
/// the final decimal ratios after this conversion, so build import and manual
/// editing share the same calculation path.
struct NativeRivenDraft: Hashable {
    var enabled = false
    var name = "自定义紫卡"
    /// 紫卡必须占用一个普通 Mod 槽；它决定元素词条参与合成的顺序。
    var slot: Int?
    /// Which actual Riven terms are present.  Values can be negative for a
    /// curse; the set deliberately does not encode a fake category hierarchy.
    var selectedStats: Set<NativeRivenStat> = []
    /// Terms preserved from the account snapshot that DamageKit does not yet
    /// have a formula for.  They remain visible to the player and are never
    /// substituted with a similarly named damage value.
    var unresolvedEffects: [InventoryData.OwnedWeapon.ImportedRiven.UnresolvedEffect] = []
    var damagePercent = 0.0
    var multishotPercent = 0.0
    var critChancePercent = 0.0
    var critDamagePercent = 0.0
    var statusChancePercent = 0.0
    var statusDurationPercent = 0.0
    var fireRatePercent = 0.0
    var reloadSpeedPercent = 0.0
    var factionPercent = 0.0
    var heatPercent = 0.0
    var coldPercent = 0.0
    var electricityPercent = 0.0
    var toxinPercent = 0.0
    var viralPercent = 0.0
    var corrosivePercent = 0.0
    var radiationPercent = 0.0
    var magneticPercent = 0.0
    var gasPercent = 0.0
    var blastPercent = 0.0
    var impactPercent = 0.0
    var puncturePercent = 0.0
    var slashPercent = 0.0
    var grineerFactionPercent = 0.0
    var corpusFactionPercent = 0.0
    var infestedFactionPercent = 0.0
    var orokinFactionPercent = 0.0

    func value(for stat: NativeRivenStat) -> Double {
        switch stat {
        case .damage: return damagePercent
        case .multishot: return multishotPercent
        case .critChance: return critChancePercent
        case .critDamage: return critDamagePercent
        case .statusChance: return statusChancePercent
        case .statusDuration: return statusDurationPercent
        case .fireRate: return fireRatePercent
        case .reloadSpeed: return reloadSpeedPercent
        case .heat: return heatPercent
        case .cold: return coldPercent
        case .electricity: return electricityPercent
        case .toxin: return toxinPercent
        case .impact: return impactPercent
        case .puncture: return puncturePercent
        case .slash: return slashPercent
        case .grineerFaction: return grineerFactionPercent
        case .corpusFaction: return corpusFactionPercent
        case .infestedFaction: return infestedFactionPercent
        case .orokinFaction: return orokinFactionPercent
        }
    }

    mutating func setValue(_ value: Double, for stat: NativeRivenStat) {
        selectedStats.insert(stat)
        switch stat {
        case .damage: damagePercent = value
        case .multishot: multishotPercent = value
        case .critChance: critChancePercent = value
        case .critDamage: critDamagePercent = value
        case .statusChance: statusChancePercent = value
        case .statusDuration: statusDurationPercent = value
        case .fireRate: fireRatePercent = value
        case .reloadSpeed: reloadSpeedPercent = value
        case .heat: heatPercent = value
        case .cold: coldPercent = value
        case .electricity: electricityPercent = value
        case .toxin: toxinPercent = value
        case .impact: impactPercent = value
        case .puncture: puncturePercent = value
        case .slash: slashPercent = value
        case .grineerFaction: grineerFactionPercent = value
        case .corpusFaction: corpusFactionPercent = value
        case .infestedFaction: infestedFactionPercent = value
        case .orokinFaction: orokinFactionPercent = value
        }
    }

    mutating func remove(_ stat: NativeRivenStat) {
        setValue(0, for: stat)
        selectedStats.remove(stat)
    }

    mutating func replace(_ old: NativeRivenStat, with new: NativeRivenStat) {
        let oldValue = value(for: old)
        remove(old)
        setValue(oldValue, for: new)
    }

    private func decimal(_ percent: Double) -> Double? {
        let value = percent / 100
        return abs(value) > .ulpOfOne ? value : nil
    }

    private var elements: [String: Double]? {
        let values = [
            "heat": heatPercent,
            "cold": coldPercent,
            "electricity": electricityPercent,
            "toxin": toxinPercent,
            "viral": viralPercent,
            "corrosive": corrosivePercent,
            "radiation": radiationPercent,
            "magnetic": magneticPercent,
            "gas": gasPercent,
            "blast": blastPercent,
        ].compactMapValues(decimal)
        return values.isEmpty ? nil : values
    }

    private var physical: [String: Double]? {
        let values = [
            "impact": impactPercent,
            "puncture": puncturePercent,
            "slash": slashPercent,
        ].compactMapValues(decimal)
        return values.isEmpty ? nil : values
    }

    private var factionBonuses: [String: Double]? {
        let values = [
            "Grineer": grineerFactionPercent,
            "Corpus": corpusFactionPercent,
            "Infested": infestedFactionPercent,
            "Orokin": orokinFactionPercent,
        ].compactMapValues(decimal)
        return values.isEmpty ? nil : values
    }

    var resolved: Riven? {
        guard enabled else { return nil }
        return Riven(name: name,
                     damage: decimal(damagePercent),
                     multishot: decimal(multishotPercent),
                     critChance: decimal(critChancePercent),
                     critDamage: decimal(critDamagePercent),
                     statusChance: decimal(statusChancePercent),
                     statusDuration: decimal(statusDurationPercent),
                     fireRate: decimal(fireRatePercent),
                     reloadSpeed: decimal(reloadSpeedPercent),
                     faction: decimal(factionPercent),
                     factionBonuses: factionBonuses,
                     elements: elements,
                     physical: physical)
    }
}

extension NativeRivenDraft {
    /// Inventory export already resolves the Riven with the same contract as
    /// DamageKit.InventoryAdapter.  This conversion only changes decimal data
    /// units into the percentage fields shown by SwiftUI.
    init(imported value: InventoryData.OwnedWeapon.ImportedRiven) {
        self.init()
        enabled = true
        name = value.name
        damagePercent = (value.damage ?? 0) * 100
        multishotPercent = (value.multishot ?? 0) * 100
        critChancePercent = (value.critChance ?? 0) * 100
        critDamagePercent = (value.critDamage ?? 0) * 100
        statusChancePercent = (value.statusChance ?? 0) * 100
        statusDurationPercent = (value.statusDuration ?? 0) * 100
        fireRatePercent = (value.fireRate ?? 0) * 100
        reloadSpeedPercent = (value.reloadSpeed ?? 0) * 100
        factionPercent = (value.faction ?? 0) * 100
        heatPercent = (value.elements?["heat"] ?? 0) * 100
        coldPercent = (value.elements?["cold"] ?? 0) * 100
        electricityPercent = (value.elements?["electricity"] ?? 0) * 100
        toxinPercent = (value.elements?["toxin"] ?? 0) * 100
        impactPercent = (value.physical?["impact"] ?? 0) * 100
        puncturePercent = (value.physical?["puncture"] ?? 0) * 100
        slashPercent = (value.physical?["slash"] ?? 0) * 100
        grineerFactionPercent = (value.factionBonuses?["Grineer"] ?? 0) * 100
        corpusFactionPercent = (value.factionBonuses?["Corpus"] ?? 0) * 100
        infestedFactionPercent = (value.factionBonuses?["Infested"] ?? 0) * 100
        orokinFactionPercent = (value.factionBonuses?["Orokin"] ?? 0) * 100
        unresolvedEffects = value.unresolved ?? []

        for stat in NativeRivenStat.allCases where abs(self.value(for: stat)) > .ulpOfOne {
            selectedStats.insert(stat)
        }
    }
}

@MainActor
final class NativeDamageCalculatorModel: ObservableObject {
    let catalog: NativeDamageCatalog
    /// Account-owned frames made available by the inventory snapshot.  A
    /// calculator opened from an Arsenal configuration receives its selected
    /// frame separately; the rest are offered only as explicitly chosen
    /// external casters.
    let availableWarframes: [InventoryData.OwnedWarframe]
    /// Actual companion bodies from the same account snapshot.  Weapon buffs
    /// come from the companion body's Mod configuration, not from a free-form
    /// list of Mod names.
    let availableCompanions: [InventoryData.OwnedEquipment]

    @Published var weaponName: String?
    /// The selected account instance, if this calculator was opened from the
    /// owned-weapons page.  It is not a public weapon definition.
    @Published private(set) var ownedWeapon: InventoryData.OwnedWeapon?
    @Published private(set) var ownedConfigIndex = 0
    @Published private(set) var ownedConfigIssues: [String] = []
    @Published private(set) var ownedConfigUnresolvedUpgrades: [InventoryData.OwnedWeapon.Config.UnresolvedUpgrade] = []
    @Published private(set) var ownedConfigIsExact = true
    @Published var enemyName: String?
    @Published var level: Int = 100
    @Published var weaponSlots: [String?] = Array(repeating: nil, count: 11)
    /// Source-proven non-max-rank values for the corresponding `weaponSlots`.
    /// A player edit clears this value, because a manually selected card is
    /// the calculator's normal full-rank data-table input rather than the
    /// previously imported physical card.
    @Published private(set) var weaponSlotActionScales: [Double?] = Array(repeating: nil, count: 11)
    /// Selected item in the equipped stance Mod's combo list.  It is passed to
    /// DamageKit as data; this model does not calculate combo timing or damage.
    @Published var stanceCombo: String?
    @Published var incarnonSelections: [Int: Int] = [:]
    @Published var riven = NativeRivenDraft()

    @Published var steelPath = false
    @Published var eximus = false
    @Published var squadSize = 1
    @Published var armorStripPercent = 0.0
    @Published var viralStacks = 0.0
    @Published var stealth = false
    /// These mirror the website's melee controls. They are raw user choices;
    /// DamageKit determines whether a selected attack is actually melee and
    /// how the relevant source-data Mod actions consume them.
    @Published var heavyAttack = false
    @Published var heavyAttackStartingCombo = 12.0
    @Published var meleeComboEnabled = true
    @Published var meleeComboMultiplier = 12.0
    /// Website options; the UI only retains whether the override is enabled
    /// and its display value. DamageKit decides whether the selected source
    /// attack is eligible and where the multiplier belongs.
    @Published var abilityComboEnabled = false
    @Published var abilityComboMultiplier = 12.0
    @Published var sniperComboEnabled = false
    @Published var sniperComboMultiplier = 1.5
    @Published var headshot = false
    @Published var weakPoint = false
    /// Only genuinely source-free environment choices remain here.  Warframe
    /// abilities are resolved from `currentWarframe` / `externalWarframeBuffs`
    /// so they cannot borrow an arbitrary manually entered percentage.
    @Published var scenarioEffectDrafts = [NativeScenarioEffectDraft(effect: .madurai)]
    @Published var distance: Double?
    @Published var window = 20.0
    @Published var conditionalStacks: [String: Double] = [:]
    /// Corresponds to warframe-damage's “All Mods conditions are met” switch.
    /// A true value writes each currently selected conditional Mod's data-table
    /// maximum into the same `conditionalStacks` input used by manual editing.
    @Published var allWeaponConditionsMaxed = true
    @Published var initialStatusStacks: [String: Double] = [:]
    /// Mirrors the website's optional manual override for CO/Gun-CO status
    /// type counting.  It is kept separate from actual pre-existing statuses.
    @Published var manualStatusCountEnabled = false
    @Published var manualStatusCount = 1.0
    /// Website option: force the per-status base-damage route into the
    /// multiplicative pool for this calculation.
    @Published var forceMultiplicativePerStatusDamage = false
    /// User-visible custom-stat values. Percentage-labelled fields stay in
    /// display units here (for example 50 means +50%); conversion to the
    /// DamageKit input contract is centralized below.
    @Published var customStatInputs: [String: Double] = [:]
    /// 对应网站攻击段下方的勾选项。武器数据的 `comb` 是候选列表；只有用户
    /// 勾选的组合才会共用状态时间线。
    @Published private(set) var selectedAttackCombinationIDs: Set<String> = []

    @Published var manualBuffs: [NativeManualBuffDraft] = []
    /// The equipped Warframe whose own self buffs and shard effects apply to
    /// this weapon.  Its A/B/C configuration is independent of every external
    /// caster configured below.
    @Published private(set) var currentWarframe: InventoryData.OwnedWarframe?
    @Published var currentWarframeConfigIndex = 0
    @Published private(set) var activeCurrentWarframeBuffIDs: Set<String> = []
    /// Each row is another actual caster.  This supports e.g. the current
    /// player’s Toxic Lash plus an ally's Roar, without merging their strength.
    @Published var externalWarframeBuffs: [NativeExternalWarframeBuffDraft] = []
    /// The one companion whose installed Mods are being considered for this
    /// weapon.  It is deliberately separate from a normal Arsenal loadout:
    /// DE stores companion presets in a distinct snapshot family.
    @Published private(set) var currentCompanion: InventoryData.OwnedEquipment?
    @Published var currentCompanionConfigIndex = 0
    /// A card being installed is not proof that its in-mission trigger is
    /// live.  Keep current trigger state separate from the imported build.
    @Published private(set) var activeCurrentCompanionBuffIDs: Set<String> = []
    @Published private(set) var currentCompanionConditionValues: [String: Double] = [:]

    @Published private(set) var selectedWeapon: Weapon?
    @Published private(set) var selectedEnemy: Enemy?
    @Published private(set) var result: DamageKit.Result?
    @Published private(set) var calculationError: String?
    @Published private(set) var calculating = false
    @Published private(set) var calculationDurationMilliseconds: Int?

    private var calculationGeneration = UUID()
    private var ownedProgenitorElements: [String: Double] = [:]

    init(initialWeaponName: String? = nil,
         initialOwnedWeapon: InventoryData.OwnedWeapon? = nil,
         initialOwnedWeaponConfigIndex: Int = 0,
         initialOwnedWarframe: InventoryData.OwnedWarframe? = nil,
         initialWarframeConfigIndex: Int = 0,
         availableWarframes suppliedWarframes: [InventoryData.OwnedWarframe] = [],
         availableCompanions suppliedCompanions: [InventoryData.OwnedEquipment] = [],
         catalog suppliedCatalog: NativeDamageCatalog? = nil) {
        let catalog = suppliedCatalog ?? .shared
        self.catalog = catalog
        var warframes = suppliedWarframes
        if let initialOwnedWarframe,
           !warframes.contains(where: { $0.id == initialOwnedWarframe.id }) {
            warframes.append(initialOwnedWarframe)
        }
        self.availableWarframes = warframes.sorted {
            $0.z.localizedStandardCompare($1.z) == .orderedAscending
        }
        self.availableCompanions = suppliedCompanions.sorted {
            $0.z.localizedStandardCompare($1.z) == .orderedAscending
        }
        ownedWeapon = initialOwnedWeapon
        currentWarframe = initialOwnedWarframe
        if let initialOwnedWarframe, !initialOwnedWarframe.configs.isEmpty {
            currentWarframeConfigIndex = min(
                max(0, initialWarframeConfigIndex),
                initialOwnedWarframe.configs.count - 1
            )
        } else {
            currentWarframeConfigIndex = 0
        }
        weaponName = initialOwnedWeapon?.calcName ?? initialWeaponName
        enemyName = catalog.enemies.first(where: { $0.name == "Corrupted Heavy Gunner" })?.name
            ?? catalog.enemies.first?.name
        reloadSelectedData(resetBuildWhenWeaponChanges: false)
        if let initialOwnedWeapon {
            let selectedIndex = min(
                max(0, initialOwnedWeaponConfigIndex),
                max(initialOwnedWeapon.configs.count - 1, 0)
            )
            applyOwnedConfig(at: selectedIndex, recalculate: false)
        }
    }

    /// Site slot IDs are stable: main 0...7, Exilus 8, stance 9 (melee only),
    /// and weapon Arcane 10.  A gun therefore has ten visible slots but its
    /// tenth one is 10, not the melee stance slot 9.
    var activeWeaponSlots: [Int] {
        let isMelee = selectedWeapon?.category?.caseInsensitiveCompare("Melee") == .orderedSame
        return isMelee ? Array(0...10) : Array(0...8) + [10]
    }

    var weaponSlotCount: Int {
        activeWeaponSlots.count
    }

    var selectedWeaponIsMelee: Bool {
        guard let weapon = selectedWeapon else { return false }
        if weapon.category?.caseInsensitiveCompare("Melee") == .orderedSame { return true }
        return (weapon.categories ?? []).contains {
            $0.caseInsensitiveCompare("melee") == .orderedSame
        }
    }

    var selectedWeaponIsExalted: Bool {
        selectedWeapon?.type?.caseInsensitiveCompare("Exalted Weapon") == .orderedSame
    }

    var selectedWeaponHasSniperCombo: Bool {
        selectedWeapon?.attacks.contains(where: { $0.sniperCombo }) ?? false
    }

    var selectedMods: [String] {
        activeWeaponSlots.compactMap { weaponSlots[$0] }
    }

    var selectedSlottedMods: [SlottedMod] {
        let weapon = activeWeaponSlots.compactMap { slot in
            weaponSlots[slot].map { name in
                let scale = weaponSlotActionScales.indices.contains(slot)
                    ? weaponSlotActionScales[slot]
                    : nil
                return SlottedMod(slot: slot, name: name, actionScale: scale)
            }
        }
        let shards = currentWarframe?.shards.compactMap { shard -> SlottedMod? in
            guard (0...4).contains(shard.slot), let name = shard.damageKitName else { return nil }
            return SlottedMod(slot: 23 + shard.slot, name: name)
        }
        return weapon + (shards ?? [])
    }

    var currentWarframeConfig: InventoryData.OwnedWarframe.Config? {
        currentWarframe?.config(at: currentWarframeConfigIndex)
    }

    var currentWarframeStrength: WarframeStrengthResolution {
        guard let currentWarframe else {
            return .init(multiplier: 1, contributions: [], inactiveConditionalTerms: [], importIssues: [])
        }
        return WarframeStrengthResolver.resolve(
            currentWarframe,
            configIndex: currentWarframeConfigIndex
        )
    }

    var currentWarframeCandidates: [WarframeWeaponBuffCandidate] {
        guard let currentWarframe else { return [] }
        return WarframeWeaponBuffResolver.candidates(
            for: currentWarframe,
            configIndex: currentWarframeConfigIndex,
            audience: .selfOnly
        )
    }

    var activeCurrentWarframeBuffResolutions: [WarframeWeaponBuffResolution] {
        guard let currentWarframe else { return [] }
        return currentWarframeCandidates
            .filter { activeCurrentWarframeBuffIDs.contains($0.id) }
            .map { WarframeWeaponBuffResolver.resolve($0, caster: currentWarframe,
                                                      configIndex: currentWarframeConfigIndex) }
    }

    var importedWarframeShards: [InventoryData.OwnedWarframe.Shard] {
        currentWarframe?.shards.sorted { $0.slot < $1.slot } ?? []
    }

    var currentCompanionConfig: InventoryData.OwnedEquipment.Config? {
        currentCompanion?.config(at: currentCompanionConfigIndex)
    }

    /// The only companion-owned Mod effects this app currently has an audited
    /// DamageKit path for.  Other imported Mods remain visible in Arsenal but
    /// cannot silently become weapon buffs here.
    var currentCompanionCandidates: [CompanionWeaponBuffCandidate] {
        guard let currentCompanion else { return [] }
        return CompanionWeaponBuffResolver.candidates(
            for: currentCompanion,
            configIndex: currentCompanionConfigIndex
        )
    }

    var activeCurrentCompanionSources: [ExternalEffectSource] {
        currentCompanionCandidates.compactMap { candidate in
            guard candidate.canCalculate,
                  activeCurrentCompanionBuffIDs.contains(candidate.id)
            else { return nil }
            return ExternalEffectSource(
                name: "\(candidate.companionName) · 配置 \(candidate.configurationLabel) · \(candidate.importedName)",
                mod: candidate.modName,
                active: true,
                conditionValue: candidate.requiresConditionValue
                    ? currentCompanionConditionValues[candidate.id] ?? 0
                    : nil
            )
        }
    }

    func currentCompanionConditionValue(for candidateID: String) -> Double {
        currentCompanionConditionValues[candidateID] ?? 0
    }

    var selectedWeaponModSlotCount: Int {
        selectedSlottedMods.count + (riven.enabled && riven.slot != nil ? 1 : 0)
    }

    var selectedOwnedConfig: InventoryData.OwnedWeapon.Config? {
        guard let ownedWeapon,
              ownedWeapon.configs.indices.contains(ownedConfigIndex) else { return nil }
        return ownedWeapon.configs[ownedConfigIndex]
    }

    var availableStanceCombos: [MeleeStanceCombo] {
        guard let name = weaponSlots[9], let mod = ModLibrary.shared.mod(named: name) else {
            return []
        }
        return MeleeStanceLibrary.combos(
            in: mod,
            orderedNames: ModLibrary.shared.stanceComboNames(for: mod.name)
        )
    }

    var availableRivenSlots: [Int] {
        activeWeaponSlots.filter { (0...7).contains($0) }
    }

    func isRivenPlaced(in slot: Int) -> Bool {
        riven.enabled && riven.slot == slot
    }

    var availableAttackCombinations: [[Int]] {
        guard let weapon = selectedWeapon else { return [] }
        let count = weapon.attacks.count
        return (weapon.comb ?? []).filter { group in
            group.count > 1
                && Set(group).count == group.count
                && group.allSatisfy { $0 >= 0 && $0 < count }
        }
    }

    var selectedAttackCombinationGroups: [[Int]] {
        availableAttackCombinations.filter { selectedAttackCombinationIDs.contains(combinationID($0)) }
    }

    func combinationID(_ group: [Int]) -> String {
        group.sorted().map(String.init).joined(separator: ",")
    }

    func isAttackCombinationSelected(_ group: [Int]) -> Bool {
        selectedAttackCombinationIDs.contains(combinationID(group))
    }

    func setAttackCombination(_ group: [Int], selected: Bool) {
        let id = combinationID(group)
        if selected {
            selectedAttackCombinationIDs.insert(id)
        } else {
            selectedAttackCombinationIDs.remove(id)
        }
        calculate()
    }

    func attackDisplayName(at index: Int) -> String {
        guard let weapon = selectedWeapon, weapon.attacks.indices.contains(index) else {
            return "攻击段 \(index + 1)"
        }
        let attack = weapon.attacks[index]
        let local = catalog.local(attack.name)
        return local == attack.name ? attack.name : "\(local) · \(attack.name)"
    }

    var selectedRules: [ConditionalEffectRule] {
        let modRules = selectedMods.compactMap { ModLibrary.shared.conditionalRule(named: $0) }
        let incarnonRules = selectedIncarnonOptions.compactMap { option in
            let label = option.name.split(separator: ":").first.map(String.init) ?? option.name
            return ModLibrary.shared.conditionalRule(named: label)
        }
        var seen = Set<String>()
        return (modRules + incarnonRules)
            .filter(\.requiresManualStackInput)
            .filter { seen.insert($0.mod.lowercased()).inserted }
    }

    private var selectedIncarnonOptions: [IncarnonTier.IncarnonOption] {
        guard let tiers = selectedWeapon?.incarnon else { return [] }
        return incarnonSelections.compactMap { tier, index in
            guard let node = tiers.first(where: { $0.tier == tier }),
                  node.options.indices.contains(index) else { return nil }
            return node.options[index]
        }
    }

    func externalCaster(for draft: NativeExternalWarframeBuffDraft) -> InventoryData.OwnedWarframe? {
        guard let casterID = draft.casterID else { return nil }
        if currentWarframe?.id == casterID { return currentWarframe }
        return availableWarframes.first { $0.id == casterID }
    }

    func externalCandidates(for draft: NativeExternalWarframeBuffDraft) -> [WarframeWeaponBuffCandidate] {
        guard let caster = externalCaster(for: draft) else { return [] }
        return WarframeWeaponBuffResolver.candidates(
            for: caster,
            configIndex: draft.configIndex,
            audience: .selfAndAllies
        )
    }

    func externalCandidate(for draft: NativeExternalWarframeBuffDraft) -> WarframeWeaponBuffCandidate? {
        guard let candidateID = draft.candidateID else { return nil }
        return externalCandidates(for: draft).first { $0.id == candidateID }
    }

    var activeExternalWarframeBuffResolutions: [WarframeWeaponBuffResolution] {
        externalWarframeBuffs.compactMap { draft in
            guard draft.active,
                  let caster = externalCaster(for: draft),
                  let candidate = externalCandidate(for: draft)
            else { return nil }
            return WarframeWeaponBuffResolver.resolve(candidate, caster: caster,
                                                      configIndex: draft.configIndex)
        }
    }

    private var activeWarframeBuffResolutions: [WarframeWeaponBuffResolution] {
        activeCurrentWarframeBuffResolutions + activeExternalWarframeBuffResolutions
    }

    var allEffectSources: EnvironmentEffects {
        // Warframe effects are source-bound and therefore arrive only through
        // `activeWarframeBuffResolutions`: a generic frame-Mod record without
        // its caster/config would have no defensible Ability Strength.
        let frames = activeWarframeBuffResolutions.compactMap(\.externalSource)
        let companions = activeCurrentCompanionSources
        let environment = manualBuffs.map { $0.source() }
        return EnvironmentEffects(warframeMods: frames, companionMods: companions,
                                  buffs: environment,
                                  initialStatusStacks: initialStatusStacks)
    }

    func selectWeapon(_ name: String) {
        guard weaponName != name else { return }
        ownedWeapon = nil
        ownedConfigIndex = 0
        ownedConfigIssues = []
        ownedConfigUnresolvedUpgrades = []
        ownedConfigIsExact = true
        ownedProgenitorElements = [:]
        weaponName = name
        weaponSlots = Array(repeating: nil, count: 11)
        weaponSlotActionScales = Array(repeating: nil, count: 11)
        stanceCombo = nil
        incarnonSelections = [:]
        riven = NativeRivenDraft()
        conditionalStacks = [:]
        selectedAttackCombinationIDs = []
        reloadSelectedData(resetBuildWhenWeaponChanges: false)
        calculate()
    }

    func selectOwnedConfig(_ index: Int) {
        applyOwnedConfig(at: index, recalculate: true)
    }

    func selectCurrentWarframe(_ id: String?) {
        guard let id else {
            currentWarframe = nil
            currentWarframeConfigIndex = 0
            activeCurrentWarframeBuffIDs = []
            calculate()
            return
        }
        guard let frame = availableWarframes.first(where: { $0.id == id }) else { return }
        currentWarframe = frame
        currentWarframeConfigIndex = 0
        activeCurrentWarframeBuffIDs = []
        calculate()
    }

    func selectCurrentWarframeConfig(_ index: Int) {
        guard let currentWarframe else { return }
        currentWarframeConfigIndex = clampedConfigIndex(index, for: currentWarframe)
        reconcileCurrentBuffSelection()
        calculate()
    }

    func setCurrentWarframeBuff(_ candidateID: String, active: Bool) {
        if active {
            activeCurrentWarframeBuffIDs.insert(candidateID)
        } else {
            activeCurrentWarframeBuffIDs.remove(candidateID)
        }
        calculate()
    }

    func selectCurrentCompanion(_ id: String?) {
        guard let id else {
            currentCompanion = nil
            currentCompanionConfigIndex = 0
            activeCurrentCompanionBuffIDs = []
            currentCompanionConditionValues = [:]
            calculate()
            return
        }
        guard let companion = availableCompanions.first(where: { $0.id == id }) else { return }
        currentCompanion = companion
        currentCompanionConfigIndex = 0
        // A different instance/configuration must never inherit trigger state
        // from another pet merely because a Mod name happens to match.
        activeCurrentCompanionBuffIDs = []
        currentCompanionConditionValues = [:]
        calculate()
    }

    func selectCurrentCompanionConfig(_ index: Int) {
        guard let currentCompanion else { return }
        currentCompanionConfigIndex = clampedConfigIndex(index, for: currentCompanion)
        reconcileCurrentCompanionBuffSelection()
        calculate()
    }

    func setCurrentCompanionBuff(_ candidateID: String, active: Bool) {
        guard currentCompanionCandidates.contains(where: { $0.id == candidateID && $0.canCalculate }) else {
            return
        }
        if active {
            activeCurrentCompanionBuffIDs.insert(candidateID)
        } else {
            activeCurrentCompanionBuffIDs.remove(candidateID)
        }
        calculate()
    }

    func setCurrentCompanionConditionValue(_ value: Double, for candidateID: String) {
        guard value.isFinite,
              currentCompanionCandidates.contains(where: {
                  $0.id == candidateID && $0.canCalculate && $0.requiresConditionValue
              })
        else { return }
        // The audited companion entries below use `WITH_COND` as a binary
        // present/not-present branch, not as an unverified stack curve.
        // Keep the UI value in that proven domain.
        let clamped = min(max(value, 0), 1)
        if clamped <= .ulpOfOne {
            currentCompanionConditionValues.removeValue(forKey: candidateID)
        } else {
            currentCompanionConditionValues[candidateID] = clamped
        }
        calculate()
    }

    func addExternalWarframeBuff() {
        guard let first = availableWarframes.first else { return }
        var draft = NativeExternalWarframeBuffDraft(casterID: first.id)
        draft.candidateID = externalCandidates(for: draft).first?.id
        externalWarframeBuffs.append(draft)
        calculate()
    }

    func removeExternalWarframeBuff(_ id: UUID) {
        externalWarframeBuffs.removeAll { $0.id == id }
        calculate()
    }

    func setExternalCaster(_ casterID: String?, for draftID: UUID) {
        guard let index = externalWarframeBuffs.firstIndex(where: { $0.id == draftID }) else { return }
        externalWarframeBuffs[index].casterID = casterID
        externalWarframeBuffs[index].configIndex = 0
        externalWarframeBuffs[index].candidateID = externalCandidates(for: externalWarframeBuffs[index]).first?.id
        calculate()
    }

    func setExternalCasterConfig(_ configIndex: Int, for draftID: UUID) {
        guard let index = externalWarframeBuffs.firstIndex(where: { $0.id == draftID }),
              let caster = externalCaster(for: externalWarframeBuffs[index]) else { return }
        externalWarframeBuffs[index].configIndex = clampedConfigIndex(configIndex, for: caster)
        let candidates = externalCandidates(for: externalWarframeBuffs[index])
        if !candidates.contains(where: { $0.id == externalWarframeBuffs[index].candidateID }) {
            externalWarframeBuffs[index].candidateID = candidates.first?.id
        }
        calculate()
    }

    func setExternalWarframeBuffCandidate(_ candidateID: String?, for draftID: UUID) {
        guard let index = externalWarframeBuffs.firstIndex(where: { $0.id == draftID }) else { return }
        externalWarframeBuffs[index].candidateID = candidateID
        calculate()
    }

    func setExternalWarframeBuffActive(_ active: Bool, for draftID: UUID) {
        guard let index = externalWarframeBuffs.firstIndex(where: { $0.id == draftID }) else { return }
        externalWarframeBuffs[index].active = active
        calculate()
    }

    private func clampedConfigIndex(_ index: Int, for frame: InventoryData.OwnedWarframe) -> Int {
        guard !frame.configs.isEmpty else { return 0 }
        return min(max(index, 0), frame.configs.count - 1)
    }

    private func clampedConfigIndex(_ index: Int, for companion: InventoryData.OwnedEquipment) -> Int {
        guard !companion.configs.isEmpty else { return 0 }
        return min(max(index, 0), companion.configs.count - 1)
    }

    private func reconcileCurrentBuffSelection() {
        let available = Set(currentWarframeCandidates.map(\.id))
        activeCurrentWarframeBuffIDs.formIntersection(available)
    }

    private func reconcileCurrentCompanionBuffSelection() {
        let candidates = currentCompanionCandidates
        let available = Set(candidates.filter(\.canCalculate).map(\.id))
        activeCurrentCompanionBuffIDs.formIntersection(available)
        currentCompanionConditionValues = currentCompanionConditionValues.filter { available.contains($0.key) }
    }

    private func applyOwnedConfig(at index: Int, recalculate: Bool) {
        guard let ownedWeapon, ownedWeapon.configs.indices.contains(index) else { return }
        let config = ownedWeapon.configs[index]
        ownedConfigIndex = index
        weaponName = ownedWeapon.calcName
        weaponSlots = config.normalizedSlots
        weaponSlotActionScales = config.normalizedSlotActionScales
        ownedProgenitorElements = ownedWeapon.progenitorElements
        ownedConfigIssues = config.issues
        ownedConfigUnresolvedUpgrades = config.unresolvedUpgrades
        ownedConfigIsExact = config.isExactImport
        if let imported = config.riven {
            var draft = NativeRivenDraft(imported: imported)
            draft.slot = config.rivenSlot
            riven = draft
        } else {
            riven = NativeRivenDraft()
        }
        stanceCombo = nil
        incarnonSelections = [:]
        conditionalStacks = [:]
        selectedAttackCombinationIDs = []
        reloadSelectedData(resetBuildWhenWeaponChanges: false)
        if let tiers = selectedWeapon?.incarnon {
            for (position, selectedOption) in ownedWeapon.incarnonChoices.enumerated()
                where tiers.indices.contains(position)
                    && tiers[position].options.indices.contains(selectedOption) {
                incarnonSelections[tiers[position].tier] = selectedOption
            }
        }
        if weaponSlots.indices.contains(9), weaponSlots[9] != nil {
            stanceCombo = availableStanceCombos.first?.name
        }
        pruneConditionState()
        if recalculate { calculate() }
    }

    func selectEnemy(_ name: String) {
        guard enemyName != name else { return }
        enemyName = name
        // Website enemy selection rebuilds the target panel: Steel Path,
        // Eximus, and its optional party input all start from their neutral
        // state for the newly selected enemy.  Keep that interaction contract
        // here; the core receives only the resulting data values.
        steelPath = false
        eximus = false
        squadSize = 1
        reloadSelectedData(resetBuildWhenWeaponChanges: false)
        calculate()
    }

    func setMod(_ name: String?, in slot: Int) {
        guard weaponSlots.indices.contains(slot) else { return }
        if riven.slot == slot {
            riven.slot = nil
        }
        if let name {
            for index in weaponSlots.indices where index != slot && weaponSlots[index] == name {
                weaponSlots[index] = nil
                if weaponSlotActionScales.indices.contains(index) {
                    weaponSlotActionScales[index] = nil
                }
            }
        }
        weaponSlots[slot] = name
        if weaponSlotActionScales.indices.contains(slot) {
            weaponSlotActionScales[slot] = nil
        }
        if slot == 9 {
            let validNames = availableStanceCombos.map(\.name)
            if let existing = stanceCombo, validNames.contains(existing) {
                // Keep the user's explicit choice if they re-select the same card.
            } else {
                // The website selects the first listed combo when a stance card
                // is equipped.  `availableStanceCombos` keeps that data order.
                stanceCombo = validNames.first
            }
        }
        pruneConditionState()
        calculate()
    }

    func setStanceCombo(_ name: String) {
        guard let selected = availableStanceCombos.first(where: { $0.name == name }) else { return }
        stanceCombo = selected.name
        calculate()
    }

    func setRivenSlot(_ slot: Int?) {
        guard slot == nil || availableRivenSlots.contains(slot!) else { return }
        riven.slot = slot
        if let slot {
            weaponSlots[slot] = nil
            if weaponSlotActionScales.indices.contains(slot) {
                weaponSlotActionScales[slot] = nil
            }
        }
        calculate()
    }

    func setRivenValue(_ value: Double, for stat: NativeRivenStat) {
        var draft = riven
        draft.setValue(value, for: stat)
        riven = draft
        calculate()
    }

    func addRivenStat(_ stat: NativeRivenStat) {
        var draft = riven
        draft.selectedStats.insert(stat)
        riven = draft
        calculate()
    }

    func removeRivenStat(_ stat: NativeRivenStat) {
        var draft = riven
        draft.remove(stat)
        riven = draft
        calculate()
    }

    func replaceRivenStat(_ old: NativeRivenStat, with new: NativeRivenStat) {
        guard old != new else { return }
        var draft = riven
        // Do not combine two same-named effects into a fabricated roll.
        guard !draft.selectedStats.contains(new) else { return }
        draft.replace(old, with: new)
        riven = draft
        calculate()
    }

    func setStack(_ stacks: Double, for rule: ConditionalEffectRule) {
        allWeaponConditionsMaxed = false
        conditionalStacks[rule.mod] = min(max(stacks, 0), rule.maxStacks)
        calculate()
    }

    func setAllWeaponConditionsMaxed(_ enabled: Bool) {
        allWeaponConditionsMaxed = enabled
        if enabled {
            for rule in selectedRules { conditionalStacks[rule.mod] = rule.maxStacks }
        } else {
            for rule in selectedRules { conditionalStacks[rule.mod] = 0 }
        }
        calculate()
    }

    func setInitialStatus(_ type: String, stacks: Double) {
        if stacks > 0 {
            initialStatusStacks[type] = stacks
        } else {
            initialStatusStacks.removeValue(forKey: type)
        }
        calculate()
    }

    func customStatInputValue(_ key: CustomStatKey) -> Double {
        customStatInputs[key.rawValue] ?? 0
    }

    func setCustomStatInput(_ value: Double, for key: CustomStatKey) {
        guard value.isFinite else { return }
        if abs(value) <= .ulpOfOne {
            customStatInputs.removeValue(forKey: key.rawValue)
        } else {
            customStatInputs[key.rawValue] = value
        }
        calculate()
    }

    /// `Options.customStats` uses the website's internal units. This is a
    /// display-unit conversion only: BuildResolver owns all formulae and their
    /// order, so SwiftUI cannot introduce a second calculation path.
    var resolvedCustomStats: [String: Double] {
        CustomStatKey.allCases.reduce(into: [String: Double]()) { result, key in
            let displayValue = customStatInputValue(key)
            guard abs(displayValue) > .ulpOfOne else { return }
            result[key.rawValue] = key.inputValue(fromDisplayValue: displayValue)
        }
    }

    var resolvedScenarioEffects: ScenarioEffects {
        var values = Dictionary(uniqueKeysWithValues: scenarioEffectDrafts.compactMap { draft -> (ScenarioEffectID, Double)? in
            guard draft.enabled else { return nil }
            return (draft.effect, draft.effect.inputValue(fromDisplayValue: draft.percent))
        })
        // DamageKit deliberately has one value per named ability route.  If
        // several source records provide the same non-stacking squad buff, the
        // strongest active instance is the relevant one; no caller can make
        // two Roars/Nourishes stack merely by adding duplicate UI rows.
        for source in activeWarframeBuffResolutions {
            guard let effect = source.scenarioEffect else { continue }
            values[effect.effect] = max(values[effect.effect] ?? 0, effect.value)
        }
        return ScenarioEffects(values: values)
    }

    func setIncarnonSelection(_ tier: Int, index: Int) {
        incarnonSelections[tier] = index
        pruneConditionState()
        calculate()
    }

    func addManualBuff() {
        manualBuffs.append(NativeManualBuffDraft(id: UUID()))
        calculate()
    }

    func removeManualBuff(_ id: UUID) {
        manualBuffs.removeAll { $0.id == id }
        calculate()
    }

    func calculate() {
        guard let selectedWeapon, let selectedEnemy, let store = catalog.store else {
            calculationError = catalog.loadError ?? "先选择武器和敌人"
            result = nil
            return
        }
        guard !riven.enabled || riven.slot != nil else {
            calculationError = "紫卡已启用，请先选择它占用的主 Mod 槽"
            result = nil
            return
        }

        let input = DamageInput(
            weapon: selectedWeapon,
            enemy: selectedEnemy,
            level: max(1, level),
            build: Build(mods: selectedMods, slottedMods: selectedSlottedMods,
                         riven: riven.resolved, rivenSlot: riven.slot,
                          progenitorElements: ownedProgenitorElements,
                         incarnonPerks: incarnonSelections.keys.sorted().compactMap { tier in
                             incarnonSelections[tier].map { "\(tier):\($0)" }
                         }, stanceCombo: stanceCombo),
            options: Options(
                window: min(max(window, 1), 60),
                steelPath: steelPath,
                eximus: eximus,
                squadSize: min(max(squadSize, 1), 4),
                armorStrip: min(max(armorStripPercent / 100, 0), 1),
                externalViralStacks: min(max(viralStacks, 0), 10),
                conditionalModStacks: conditionalStacks,
                manualStatusTypeCount: manualStatusCountEnabled
                    ? min(max(manualStatusCount, 0), 50)
                    : nil,
                allModConditionsMet: allWeaponConditionsMaxed,
                // Ability Strength is resolved from the selected current
                // Warframe configuration.  Externally cast abilities supply
                // their own source-specific override in ExternalEffectSource.
                abilityStrength: currentWarframeStrength.multiplier,
                forceMultiplicativePerStatusDamage: forceMultiplicativePerStatusDamage,
                customStats: resolvedCustomStats,
                scenarioEffects: resolvedScenarioEffects,
                combinedAttackGroups: selectedAttackCombinationGroups,
                stealth: stealth,
                heavyAttack: heavyAttack,
                heavyAttackStartingCombo: min(max(heavyAttackStartingCombo, 1), 13),
                meleeComboMultiplier: meleeComboEnabled
                    ? min(max(meleeComboMultiplier, 1), 13)
                    : nil,
                abilityComboMultiplier: abilityComboEnabled
                    ? min(max(abilityComboMultiplier, 1), 12)
                    : nil,
                sniperComboMultiplier: sniperComboEnabled
                    ? min(max(sniperComboMultiplier, 1.5), 100)
                    : nil,
                headshot: headshot,
                distance: distance,
                weakPoint: weakPoint,
                environment: allEffectSources
            )
        )

        let generation = UUID()
        calculationGeneration = generation
        calculating = true
        calculationError = nil
        let calculator = Calculator(store: store)
        let started = DispatchTime.now().uptimeNanoseconds
        Task.detached(priority: .userInitiated) { [weak self] in
            let output = calculator.evaluate(input)
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            await MainActor.run {
                guard let self, self.calculationGeneration == generation else { return }
                self.result = output
                self.calculationDurationMilliseconds = elapsed
                self.calculating = false
            }
        }
    }

    func reloadSelectedData(resetBuildWhenWeaponChanges: Bool) {
        do {
            if let weaponName {
                selectedWeapon = try catalog.weapon(named: weaponName)
            } else {
                selectedWeapon = nil
            }
            if let enemyName {
                selectedEnemy = try catalog.enemy(named: enemyName)
            } else {
                selectedEnemy = nil
            }
            calculationError = nil
        } catch {
            selectedWeapon = nil
            selectedEnemy = nil
            calculationError = "读取计算对象失败：\(error.localizedDescription)"
        }
    }

    private func pruneConditionState() {
        let rules = selectedRules
        let allowed = Set(rules.map(\.mod))
        conditionalStacks = conditionalStacks.filter { allowed.contains($0.key) }
        if allWeaponConditionsMaxed {
            for rule in rules { conditionalStacks[rule.mod] = rule.maxStacks }
        }
    }
}
