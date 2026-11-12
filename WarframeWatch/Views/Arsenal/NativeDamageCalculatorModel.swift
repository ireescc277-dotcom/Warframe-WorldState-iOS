import Combine
import Dispatch
import Foundation
import DamageKit

enum NativeEffectGroup: String, CaseIterable, Identifiable {
    case warframe
    case companion
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warframe: return "战甲 Mod / 赋能"
        case .companion: return "同伴 Mod"
        case .environment: return "其他环境效果"
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

/// A selected external Mod together with the state that makes it active now.
/// The Mod name is resolved through DamageKit; no UI label is interpreted as a
/// formula.
struct NativeEffectDraft: Identifiable, Hashable {
    let id: UUID
    var group: NativeEffectGroup
    var modName: String
    var active: Bool
    /// Nil means that a conditional external effect is not assumed to be on.
    var conditionValue: Double?

    init(group: NativeEffectGroup, modName: String, active: Bool = true,
         conditionValue: Double? = nil) {
        id = UUID()
        self.group = group
        self.modName = modName
        self.active = active
        self.conditionValue = conditionValue
    }

    func source() -> ExternalEffectSource {
        ExternalEffectSource(name: modName, mod: modName, active: active,
                             conditionValue: conditionValue)
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

/// Manual Riven fields use user-facing percentage units.  DamageKit receives
/// the final decimal ratios after this conversion, so build import and manual
/// editing share the same calculation path.
struct NativeRivenDraft: Hashable {
    var enabled = false
    var name = "自定义紫卡"
    /// 紫卡必须占用一个普通 Mod 槽；它决定元素词条参与合成的顺序。
    var slot: Int?
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
    }
}

@MainActor
final class NativeDamageCalculatorModel: ObservableObject {
    let catalog: NativeDamageCatalog

    @Published var weaponName: String?
    /// The selected account instance, if this calculator was opened from the
    /// owned-weapons page.  It is not a public weapon definition.
    @Published private(set) var ownedWeapon: InventoryData.OwnedWeapon?
    @Published private(set) var ownedConfigIndex = 0
    @Published private(set) var ownedConfigIssues: [String] = []
    @Published private(set) var ownedConfigIsExact = true
    @Published var enemyName: String?
    @Published var level: Int = 100
    @Published var weaponSlots: [String?] = Array(repeating: nil, count: 11)
    /// Selected item in the equipped stance Mod's combo list.  It is passed to
    /// DamageKit as data; this model does not calculate combo timing or damage.
    @Published var stanceCombo: String?
    /// Site-equivalent Archon Shard positions are 23...27. They are separate
    /// from weapon Mod slots and remain when the equipped weapon changes.
    @Published var archonShardSlots: [String?] = Array(repeating: nil, count: 5)
    @Published var incarnonSelections: [Int: Int] = [:]
    @Published var riven = NativeRivenDraft()

    @Published var steelPath = false
    @Published var eximus = false
    @Published var squadSize = 1
    @Published var armorStripPercent = 0.0
    @Published var viralStacks = 0.0
    /// The single website-wide Strength field, in user-facing percent units.
    /// It is converted once when Options is constructed; individual external
    /// Mod rows do not own competing strength values.
    @Published var abilityStrengthPercent = 100.0
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
    /// Website-named scenario effects whose formula locations are owned by
    /// DamageKit. This UI state contains only IDs, selection state, and display
    /// values; it does not encode named damage formulae.
    @Published var scenarioEffectDrafts = ScenarioEffectID.allCases.map {
        NativeScenarioEffectDraft(effect: $0)
    }
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

    @Published var externalEffects: [NativeEffectDraft] = []
    @Published var manualBuffs: [NativeManualBuffDraft] = []

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
         catalog suppliedCatalog: NativeDamageCatalog? = nil) {
        let catalog = suppliedCatalog ?? .shared
        self.catalog = catalog
        ownedWeapon = initialOwnedWeapon
        weaponName = initialOwnedWeapon?.calcName ?? initialWeaponName
        enemyName = catalog.enemies.first(where: { $0.name == "Corrupted Heavy Gunner" })?.name
            ?? catalog.enemies.first?.name
        reloadSelectedData(resetBuildWhenWeaponChanges: false)
        if initialOwnedWeapon != nil {
            applyOwnedConfig(at: 0, recalculate: false)
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
            weaponSlots[slot].map { SlottedMod(slot: slot, name: $0) }
        }
        let shards = archonShardSlots.enumerated().compactMap { index, name in
            name.map { SlottedMod(slot: 23 + index, name: $0) }
        }
        return weapon + shards
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

    func effects(in group: NativeEffectGroup) -> [NativeEffectDraft] {
        externalEffects.filter { $0.group == group }
    }

    var allEffectSources: EnvironmentEffects {
        let frames = effects(in: .warframe).map { $0.source() }
        let companions = effects(in: .companion).map { $0.source() }
        let environment = effects(in: .environment).map { $0.source() }
            + manualBuffs.map { $0.source() }
        return EnvironmentEffects(warframeMods: frames, companionMods: companions,
                                  buffs: environment,
                                  initialStatusStacks: initialStatusStacks)
    }

    func selectWeapon(_ name: String) {
        guard weaponName != name else { return }
        ownedWeapon = nil
        ownedConfigIndex = 0
        ownedConfigIssues = []
        ownedConfigIsExact = true
        ownedProgenitorElements = [:]
        weaponName = name
        weaponSlots = Array(repeating: nil, count: 11)
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

    private func applyOwnedConfig(at index: Int, recalculate: Bool) {
        guard let ownedWeapon, ownedWeapon.configs.indices.contains(index) else { return }
        let config = ownedWeapon.configs[index]
        ownedConfigIndex = index
        weaponName = ownedWeapon.calcName
        weaponSlots = config.normalizedSlots
        ownedProgenitorElements = ownedWeapon.progenitorElements
        ownedConfigIssues = config.issues
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
            }
        }
        weaponSlots[slot] = name
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
        }
        calculate()
    }

    func setArchonShard(_ name: String?, in slot: Int) {
        guard archonShardSlots.indices.contains(slot) else { return }
        archonShardSlots[slot] = name
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
        ScenarioEffects(values: Dictionary(uniqueKeysWithValues: scenarioEffectDrafts.compactMap { draft in
            guard draft.enabled else { return nil }
            return (draft.effect, draft.effect.inputValue(fromDisplayValue: draft.percent))
        }))
    }

    func setIncarnonSelection(_ tier: Int, index: Int) {
        incarnonSelections[tier] = index
        pruneConditionState()
        calculate()
    }

    func addExternalMod(_ name: String, to group: NativeEffectGroup) {
        guard !externalEffects.contains(where: { $0.group == group && $0.modName == name }) else { return }
        externalEffects.append(NativeEffectDraft(group: group, modName: name))
        calculate()
    }

    func removeExternalEffect(_ id: UUID) {
        externalEffects.removeAll { $0.id == id }
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
                abilityStrength: max(0, abilityStrengthPercent / 100),
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
