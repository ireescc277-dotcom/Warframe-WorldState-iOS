import SwiftUI
import DamageKit
#if canImport(UIKit)
import UIKit
#endif

private enum NativeCalcSheet: Identifiable {
    case weapon
    case enemy
    case mod(slot: Int)

    var id: String {
        switch self {
        case .weapon: return "weapon"
        case .enemy: return "enemy"
        case .mod(let slot): return "mod-\(slot)"
        }
    }
}

private extension ScenarioEffectID {
    /// Abilities with a Warframe source are intentionally absent here.  They
    /// are selected via the current Warframe or an external caster below,
    /// never presented as source-free environment switches.
    var nativeGroup: NativeEffectGroup? {
        switch self {
        case .roar, .eclipse, .nourish, .xata, .toxicLash:
            return nil
        case .flatCriticalChance, .madurai:
            return .environment
        }
    }

    var nativeDisplayName: String {
        switch self {
        case .roar: return "咆哮（Rhino）"
        case .eclipse: return "日蚀（Mirage）"
        case .nourish: return "滋养（Grendel）"
        case .xata: return "虚空低语（Xata）"
        case .toxicLash: return "毒鞭（Saryn）"
        case .flatCriticalChance: return "绝对暴击率"
        case .madurai: return "马杜莱学派"
        }
    }

    var nativeDisplayDetail: String {
        switch self {
        case .roar: return "派系伤害；状态伤害沿用派系二次结算"
        case .eclipse: return "最终外放伤害倍率；直击与伤害型状态在各自最终阶段结算"
        case .nourish: return "以 Modded Base 计，在槽位元素合并后追加 Viral"
        case .xata: return "独立 Void 直击；按网站的特殊派系与防御结算路径处理"
        case .toxicLash: return "每颗弹丸额外造成 Toxin 直击与独立持续伤害；近战为 2 倍系数"
        case .flatCriticalChance: return "在普通 Mod 后、最终暴击率乘算前加入"
        case .madurai: return "固定 +30% 直击伤害；不作用于 POWER_WEAPON 与伤害型状态"
        }
    }

    var nativeDisplayUnit: String {
        self == .flatCriticalChance ? "pp" : "%"
    }
}

/// Native SwiftUI implementation of the damage calculator.  It intentionally
/// owns the same selection operations as the previous website shell — weapon,
/// target, Mod slots, Incarnon choices, condition state, external sources, and
/// results — but calculations now call DamageKit directly.
struct NativeDamageCalculatorView: View {
    let title: String
    @StateObject private var model: NativeDamageCalculatorModel
    @State private var sheet: NativeCalcSheet?
    @State private var showAdvanced = false
    /// Simulator screenshots cannot tap or scroll.  This launch-only flag is
    /// deliberately separate from normal calculator state: it lets CI prove
    /// that an actual result renders after DamageKit has completed, without
    /// changing what a player sees when entering the calculator.
    private let autoRevealResults: Bool
    /// CI-only screenshot hook for the account-bound companion source card.
    /// It never selects or enables a companion during ordinary app use.
    private let autoRevealCompanion: Bool
    private let resultsAnchor = "native-damage-results"
    private let companionAnchor = "native-damage-companion"

    init(weapon: String? = nil,
         ownedWeapon: InventoryData.OwnedWeapon? = nil,
         ownedWeaponConfigIndex: Int = 0,
         ownedWarframe: InventoryData.OwnedWarframe? = nil,
         warframeConfigIndex: Int = 0,
         availableWarframes: [InventoryData.OwnedWarframe] = [],
         availableCompanions: [InventoryData.OwnedEquipment] = [],
         title: String = "伤害计算") {
        self.title = title
        _model = StateObject(wrappedValue: NativeDamageCalculatorModel(
            initialWeaponName: weapon,
            initialOwnedWeapon: ownedWeapon,
            initialOwnedWeaponConfigIndex: ownedWeaponConfigIndex,
            initialOwnedWarframe: ownedWarframe,
            initialWarframeConfigIndex: warframeConfigIndex,
            availableWarframes: availableWarframes,
            availableCompanions: availableCompanions
        ))
        autoRevealResults = CommandLine.arguments.contains("-calcResult")
        autoRevealCompanion = CommandLine.arguments.contains("-calcCompanion")
    }

    var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        heading
                        if let error = model.catalog.loadError {
                            problemCard(error)
                        } else {
                            selectionCard
                            attackCombinationCard
                            targetCard
                            buildCard
                            incarnonCard
                            conditionCard
                            warframeCard
                            companionCard.id(companionAnchor)
                            environmentCard
                            advancedCard
                            calculationButton
                            resultsCard.id(resultsAnchor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                }
                .onChange(of: model.calculating) { calculating in
                    guard autoRevealResults, !calculating, model.result != nil else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(resultsAnchor, anchor: .top)
                        }
                    }
                }
                .onAppear {
                    guard autoRevealCompanion else { return }
                    if model.currentCompanion == nil,
                       let companion = model.availableCompanions.first {
                        model.selectCurrentCompanion(companion.id)
                    }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(companionAnchor, anchor: .top)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WFTheme.bgSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { model.calculate() }
        .sheet(item: $sheet) { target in
            switch target {
            case .weapon:
                NativeWeaponPicker(model: model) { name in
                    model.selectWeapon(name)
                    sheet = nil
                }
            case .enemy:
                NativeEnemyPicker(model: model) { name in
                    model.selectEnemy(name)
                    sheet = nil
                }
            case .mod(let slot):
                NativeModPicker(model: model, slot: slot) { name in
                    model.setMod(name, in: slot)
                    sheet = nil
                }
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("伤害计算")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                Text("原生 Swift · 当前配置在本机计算")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
            }
            Spacer()
            if model.calculating {
                ProgressView().tint(WFTheme.gold)
            } else if let elapsed = model.calculationDurationMilliseconds {
                Text("\(elapsed) ms")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
    }

    private func problemCard(_ message: String) -> some View {
        WFCard(isHighlighted: true) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.wfBody)
                .foregroundColor(WFTheme.red)
            Text("请重新安装完整版本后再试。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("武器与目标")
            Button { sheet = .weapon } label: {
                selectionRow(
                    title: "武器",
                    primary: selectedWeaponLabel,
                    secondary: selectedWeaponDetail,
                    image: selectedWeaponEntry.flatMap { model.catalog.localWeaponIcon(named: $0.img) },
                    remote: selectedWeaponEntry?.iconURL
                )
            }
            .buttonStyle(.plain)
            if let owned = model.ownedWeapon {
                WFHairline()
                ownedConfigRow(owned)
            }
            WFHairline()
            Button { sheet = .enemy } label: {
                selectionRow(
                    title: "敌人",
                    primary: selectedEnemyLabel,
                    secondary: selectedEnemyDetail,
                    image: nil,
                    remote: nil
                )
            }
            .buttonStyle(.plain)
        }
        .wfCardStyle()
    }

    private func ownedConfigRow(_ owned: InventoryData.OwnedWeapon) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: WFUI.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("背包配卡")
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textSecondary)
                    Text("已带入这把武器实例的槽位与固有元素；可继续手动调整")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: WFUI.s2)
                if !owned.configs.isEmpty {
                    Picker("背包配卡", selection: ownedConfigBinding) {
                        ForEach(Array(owned.configs.enumerated()), id: \.offset) { index, config in
                            Text("配置 \(config.label)").tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WFTheme.gold)
                }
            }
            if !model.ownedConfigIsExact {
                Label("以下来源槽位没有计入当前结果；它们没有被按满级或空槽处理。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
                ForEach(model.ownedConfigUnresolvedUpgrades) { upgrade in
                    let rank = upgrade.rankLabel.map { "，\($0)" } ?? ""
                    Text("• \(slotLabel(upgrade.slot))：\(upgrade.name)\(rank)。\(upgrade.reason)")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                ForEach(model.ownedConfigIssues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
            }
        }
    }

    private var ownedConfigBinding: Binding<Int> {
        Binding(get: { model.ownedConfigIndex }, set: { model.selectOwnedConfig($0) })
    }

    @ViewBuilder
    private var attackCombinationCard: some View {
        if !model.availableAttackCombinations.isEmpty {
            VStack(alignment: .leading, spacing: WFUI.s2) {
                WFSectionHeader("攻击段合并", trailing: "与网站默认一致：默认不合并")
                Text("只有确实会在同一发命中同一目标的攻击段才勾选。勾选后它们共用状态层数与 DOT 时间线；不勾选则分别结算。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                ForEach(Array(model.availableAttackCombinations.enumerated()), id: \.offset) { _, group in
                    Toggle(isOn: attackCombinationBinding(group)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.map(model.attackDisplayName(at:)).joined(separator: " + "))
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textPrimary)
                            Text("共用同一次命中的状态时间线")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textSecondary)
                        }
                    }
                    .tint(WFTheme.gold)
                }
            }
            .wfCardStyle()
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("目标设置", trailing: "与网站同类选项")
            HStack {
                Text("等级").font(.wfBody).foregroundColor(WFTheme.textSecondary)
                Spacer()
                Stepper(value: $model.level, in: 1...9999) {
                    Text("\(model.level)").font(.wfNumSmall).foregroundColor(WFTheme.textPrimary)
                }
                .frame(width: 142)
                .onChange(of: model.level) { _ in model.calculate() }
            }
            Toggle("钢铁之路", isOn: $model.steelPath)
                .tint(WFTheme.gold)
                .font(.wfBody)
                .foregroundColor(WFTheme.textPrimary)
                .onChange(of: model.steelPath) { _ in model.calculate() }
            Toggle("卓越者", isOn: $model.eximus)
                .tint(WFTheme.gold)
                .font(.wfBody)
                .foregroundColor(WFTheme.textPrimary)
                .onChange(of: model.eximus) { _ in model.calculate() }
            if model.selectedEnemy?.showPartyCount == true {
                HStack {
                    Text("小队人数").font(.wfBody).foregroundColor(WFTheme.textSecondary)
                    Spacer()
                    Stepper(value: $model.squadSize, in: 1...4) {
                        Text("\(model.squadSize) 人").font(.wfNumSmall).foregroundColor(WFTheme.textPrimary)
                    }
                    .frame(width: 142)
                    .onChange(of: model.squadSize) { _ in model.calculate() }
                }
                Text("该敌人在网站数据中启用小队人数：只改变生命，2/3/4 人分别为 ×1.5/×2/×3。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            HStack(spacing: WFUI.s2) {
                DamageNumberField("外部削甲", value: $model.armorStripPercent, suffix: "%")
                DamageNumberField("外部病毒", value: $model.viralStacks, suffix: "层")
            }
            .onChange(of: model.armorStripPercent) { _ in model.calculate() }
            .onChange(of: model.viralStacks) { _ in model.calculate() }
        }
        .wfCardStyle()
    }

    private var buildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("武器配卡", trailing: "\(model.selectedWeaponModSlotCount) / \(model.weaponSlotCount)")
            if model.selectedWeapon == nil {
                Text("先选一把武器，Mod 会按适用标签过滤。")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WFUI.s2) {
                    ForEach(model.activeWeaponSlots, id: \.self) { slot in
                        Button { sheet = .mod(slot: slot) } label: {
                            modSlot(slot)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !model.availableStanceCombos.isEmpty {
                    stanceComboControls
                }
                rivenControls
            }
        }
        .wfCardStyle()
    }

    private var stanceComboControls: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Text("架势连段")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            Picker("架势连段", selection: stanceComboBinding) {
                ForEach(model.availableStanceCombos, id: \.name) { combo in
                    Text(model.catalog.local(combo.name)).tag(combo.name)
                }
            }
            .pickerStyle(.menu)
            .tint(WFTheme.gold)
            Text("所选连段的周期、每一击倍率和强制异常由该架势 Mod 的原始数据交给计算内核。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func modSlot(_ slot: Int) -> some View {
        let isRiven = model.isRivenPlaced(in: slot)
        let selected = isRiven ? nil : model.weaponSlots[slot]
        return HStack(spacing: 8) {
            if let selected, let mod = ModLibrary.shared.mod(named: selected) {
                NativeThumb(local: model.catalog.localModIcon(for: mod),
                            remote: model.catalog.iconURL(for: mod), size: 30)
            } else if isRiven {
                NativeThumb(local: model.catalog.localModIcon(named: "riven.webp"),
                            remote: URL(string: "https://warframe-damage.com/data/mods/riven.webp"), size: 30)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
                    .frame(width: 30, height: 30)
                    .background(WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(slotLabel(slot))
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                Text(isRiven ? "自定义紫卡" : (selected.map(model.catalog.local) ?? "选择 Mod"))
                    .font(.wfBody)
                    .foregroundColor(selected == nil && !isRiven ? WFTheme.textSecondary : WFTheme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected != nil || isRiven {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(WFTheme.textMuted)
                    .onTapGesture {
                        if isRiven {
                            model.setRivenSlot(nil)
                        } else {
                            model.setMod(nil, in: slot)
                        }
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rivenControls: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Toggle("紫卡（占用一个武器 Mod 槽）", isOn: $model.riven.enabled)
                .tint(WFTheme.gold)
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            if model.riven.enabled {
                Picker("紫卡占用槽位", selection: rivenSlotBinding) {
                    Text("请选择主 Mod 槽").tag(Int?.none)
                    ForEach(model.availableRivenSlots, id: \.self) { slot in
                        Text(slotLabel(slot)).tag(Optional(slot))
                    }
                }
                .pickerStyle(.menu)
                .tint(WFTheme.gold)
                TextField("紫卡名称", text: $model.riven.name)
                    .textFieldStyle(.roundedBorder)
                if model.riven.selectedStats.isEmpty {
                    Text("尚未添加词条。导入背包中的紫卡后，会把已解析的实际词条逐条列在这里。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                ForEach(model.riven.selectedStats.sorted { $0.rawValue < $1.rawValue }, id: \.self) { stat in
                    rivenStatEditor(stat)
                }
                if !model.riven.unresolvedEffects.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("以下紫卡原始词条已读取，但当前没有对应的伤害规则，因此没有写入计算：",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                        ForEach(model.riven.unresolvedEffects) { effect in
                            Text("• \(effect.label)（\(effect.tag)）")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                    .padding(9)
                    .background(WFUI.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Menu {
                    ForEach(NativeRivenStatGroup.allCases) { group in
                        let choices = rivenAvailableStats(in: group)
                        if !choices.isEmpty {
                            Section(group.title) {
                                ForEach(choices, id: \.self) { stat in
                                    Button(stat.title) { model.addRivenStat(stat) }
                                }
                            }
                        }
                    }
                } label: {
                    Label("添加紫卡词条", systemImage: "plus.circle")
                        .font(.wfBody)
                        .foregroundColor(WFTheme.gold)
                }
                Text("每一行就是一条实际紫卡词条；可填负数作为负面。元素、物理与阵营词条都和其他词条处在同一层级。不会额外捏造“任意元素”或“泛用派系”输入；背包导入的特殊原始词条会单独显示。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
        .onChange(of: model.riven) { _ in model.calculate() }
    }

    private func rivenAvailableStats(in group: NativeRivenStatGroup) -> [NativeRivenStat] {
        NativeRivenStat.allCases.filter {
            $0.group == group && !model.riven.selectedStats.contains($0)
        }
    }

    private func rivenStatEditor(_ stat: NativeRivenStat) -> some View {
        HStack(alignment: .bottom, spacing: WFUI.s2) {
            Menu {
                ForEach(NativeRivenStatGroup.allCases) { group in
                    let choices = NativeRivenStat.allCases.filter {
                        $0.group == group && ($0 == stat || !model.riven.selectedStats.contains($0))
                    }
                    if !choices.isEmpty {
                        Section(group.title) {
                            ForEach(choices, id: \.self) { candidate in
                                Button(candidate.title) { model.replaceRivenStat(stat, with: candidate) }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(stat.title)
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(WFTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 9)
                .background(WFUI.raised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            DamageNumberField("数值", value: rivenStatBinding(stat), suffix: "%", allowsNegative: true)
                .frame(width: 106)
            Button(role: .destructive) { model.removeRivenStat(stat) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(WFTheme.red)
            .padding(.bottom, 9)
        }
        .padding(9)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var archonShardControls: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Text("执政官石")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            Text("石头装在战甲上；这里直接读取当前战甲实例，不提供与背包无关的手填石槽。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            if model.currentWarframe == nil {
                Text("先选择背包中的战甲，才能读取它装备的执政官石。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else if model.importedWarframeShards.isEmpty {
                Text("这名战甲在当前背包快照中没有已装执政官石。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                ForEach(model.importedWarframeShards) { shard in
                    archonShardRow(shard)
                }
            }
        }
        .padding(.top, WFUI.s2)
    }

    private func archonShardRow(_ shard: InventoryData.OwnedWarframe.Shard) -> some View {
        return HStack(spacing: 8) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(WFTheme.gold)
                .frame(width: 30, height: 30)
                .background(WFTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("石槽 \(shard.slot + 1)")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                Text(shard.name)
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(1)
                Text(shard.damageKitName == nil
                     ? "已读取；它不改变当前武器伤害，所以不写入本次伤害计算。"
                     : "已随当前战甲写入本次伤害计算。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var incarnonCard: some View {
        if let weapon = model.selectedWeapon, let tiers = weapon.incarnon, !tiers.isEmpty {
            VStack(alignment: .leading, spacing: WFUI.s3) {
                WFSectionHeader("灵化进化")
                ForEach(tiers, id: \.tier) { tier in
                    Picker("第 \(tier.tier) 层", selection: incarnonBinding(tier.tier)) {
                        ForEach(Array(tier.options.enumerated()), id: \.offset) { index, option in
                            Text(option.name.isEmpty
                                 ? "选项 \(index + 1)"
                                 : model.catalog.localIncarnon(option.name))
                                .font(.wfBody)
                                .tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WFTheme.gold)
                    let selectedIndex = model.incarnonSelections[tier.tier] ?? 0
                    if tier.options.indices.contains(selectedIndex) {
                        let selected = tier.options[selectedIndex].name
                        if !selected.isEmpty {
                            Text(model.catalog.localIncarnon(selected))
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textSecondary)
                            if model.catalog.localIncarnon(selected) != selected {
                                Text(selected)
                                    .font(.wfLabel)
                                    .foregroundColor(WFTheme.textMuted)
                            }
                        }
                    }
                }
            }
            .wfCardStyle()
        }
    }

    @ViewBuilder
    private var conditionCard: some View {
        if !model.selectedRules.isEmpty {
            VStack(alignment: .leading, spacing: WFUI.s3) {
                WFSectionHeader("已满足的武器条件", trailing: "层数来自规则数据")
                Toggle("所有武器条件按满层", isOn: allConditionsBinding)
                    .tint(WFTheme.gold)
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textPrimary)
                Text("对应 warframe-damage 的 “All Mods conditions are met”；关闭后可逐张调整。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                if !model.allWeaponConditionsMaxed {
                    ForEach(model.selectedRules, id: \.mod) { rule in
                        let inputMaximum = model.conditionalInputMaximum(for: rule)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.catalog.local(rule.mod))
                                    .font(.wfBody)
                                    .foregroundColor(WFTheme.textPrimary)
                                Text("\(inputMaximum.cleanNumber) \(rule.inputLabel ?? "层")封顶 · \(rule.mode == .totalRelativeToStaticAction ? "满层总值插值" : "满层额外值")")
                                    .font(.wfLabel)
                                    .foregroundColor(WFTheme.textMuted)
                            }
                            Spacer()
                            Stepper(value: stackBinding(rule), in: 0...inputMaximum, step: 1) {
                                Text("\((model.conditionalStacks[rule.mod] ?? 0).cleanNumber) \(rule.inputLabel ?? "层")")
                                    .font(.wfNumSmall)
                                    .foregroundColor(WFTheme.gold)
                            }
                            .frame(width: 120)
                        }
                    }
                }
            }
            .wfCardStyle()
        }
    }

    private var warframeCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("战甲")
            Text("技能强度不手填。当前战甲与外部施法者各自从其 A/B/C 配置、Mod 和执政官石结算，互不借用数值。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            currentWarframeSelection
            if let frame = model.currentWarframe {
                currentWarframeConfiguration(frame)
                currentWarframeStrengthSummary
                archonShardControls
                currentWarframeBuffControls
            } else {
                Text("未选择当前战甲：本次武器按 100% 技能强度且不带战甲石头或自身技能计算。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            WFHairline()
            externalWarframeBuffControls
        }
        .wfCardStyle()
    }

    private var currentWarframeSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前战甲")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            if model.availableWarframes.isEmpty {
                Text("这次打开计算器时没有传入背包战甲；从军械库的整套配置进入后会自动带入。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                Menu {
                    Button("不使用战甲来源") { model.selectCurrentWarframe(nil) }
                    Divider()
                    ForEach(model.availableWarframes) { frame in
                        Button(frame.z) { model.selectCurrentWarframe(frame.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.square")
                            .foregroundColor(WFTheme.gold)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.currentWarframe?.z ?? "选择背包中的战甲")
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textPrimary)
                            Text(model.currentWarframe.map { _ in "使用它的 A/B/C 配置" } ?? "不带战甲来源")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(WFTheme.textMuted)
                    }
                    .padding(10)
                    .background(WFUI.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func currentWarframeConfiguration(_ frame: InventoryData.OwnedWarframe) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Text("战甲配置")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            HStack(spacing: 6) {
                ForEach(Array(frame.configs.enumerated()), id: \.element.id) { entry in
                    let index = entry.offset
                    let config = entry.element
                    Button {
                        model.selectCurrentWarframeConfig(index)
                    } label: {
                        Text(config.label)
                            .font(.wfBody)
                            .foregroundColor(index == model.currentWarframeConfigIndex
                                             ? Color(hex: "1A1408") : WFTheme.textSecondary)
                            .frame(minWidth: 34)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(index == model.currentWarframeConfigIndex
                                                        ? WFTheme.gold : WFUI.raised))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let config = model.currentWarframeConfig, !config.isExactImport {
                Text(config.issues.joined(separator: "\n"))
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            }
        }
    }

    private var currentWarframeStrengthSummary: some View {
        let strength = model.currentWarframeStrength
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("已结算技能强度")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                Spacer()
                Text("\(strength.percent)%")
                    .font(.wfNumSmall)
                    .foregroundColor(WFTheme.gold)
            }
            if strength.contributions.isEmpty {
                Text("没有常驻技能强度词条；以 100% 计算。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                ForEach(strength.contributions) { contribution in
                    HStack {
                        Text(contribution.label)
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                        Spacer()
                        Text(String(format: "%+.0f%%", contribution.value * 100))
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textSecondary)
                    }
                }
            }
            if !strength.inactiveConditionalTerms.isEmpty {
                Text("以下卡片有触发条件，当前未自动算入：\(strength.inactiveConditionalTerms.joined(separator: "；"))")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var currentWarframeBuffControls: some View {
        let candidates = model.currentWarframeCandidates
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            Text("当前战甲自身技能")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            Text("只列出这名战甲当前配置实际拥有、且已接入 DamageKit 公式的武器增益。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            if candidates.isEmpty {
                Text("这套配置没有已接入的自身武器增益。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                ForEach(candidates) { candidate in
                    currentWarframeBuffRow(candidate)
                }
            }
        }
    }

    private func currentWarframeBuffRow(_ candidate: WarframeWeaponBuffCandidate) -> some View {
        let enabled = model.activeCurrentWarframeBuffIDs.contains(candidate.id)
        // The display resolution is useful even before the toggle is enabled;
        // it tells the player exactly what this configuration would provide.
        let preview = model.currentWarframe.map {
            WarframeWeaponBuffResolver.resolve(candidate, caster: $0,
                                                configIndex: model.currentWarframeConfigIndex)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: WFUI.s2) {
                Toggle("", isOn: currentWarframeBuffBinding(candidate.id))
                    .labelsHidden()
                    .tint(WFTheme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textPrimary)
                    Text(candidate.detail)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Spacer(minLength: 0)
                if let preview {
                    Text(warframeBuffValueLabel(preview))
                        .font(.wfLabel)
                        .foregroundColor(enabled ? WFTheme.gold : WFTheme.textMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var externalWarframeBuffControls: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            HStack {
                Text("外部施法战甲 Buff")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                Spacer()
                Button("添加") { model.addExternalWarframeBuff() }
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
                    .disabled(model.availableExternalWarframes.isEmpty)
            }
            Text("每一行是一条外部施放来源。选择其他施法者、其 A/B/C 配置和实际可给队友的技能；它的技能强度不会使用当前战甲的配置，当前战甲也不能重复作为外部来源。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            if model.availableExternalWarframes.isEmpty {
                Text("没有可选择的其他背包战甲。当前战甲仅在上方按自身来源结算，不会重复计入这里。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else if model.externalWarframeBuffs.isEmpty {
                Text("尚未添加外部施法者。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                ForEach(model.externalWarframeBuffs) { draft in
                    externalWarframeBuffEditor(draft)
                }
            }
        }
    }

    private func externalWarframeBuffEditor(_ draft: NativeExternalWarframeBuffDraft) -> some View {
        let caster = model.externalCaster(for: draft)
        let candidates = model.externalCandidates(for: draft)
        let selected = model.externalCandidate(for: draft)
        let preview: WarframeWeaponBuffResolution? = {
            guard let caster, let selected else { return nil }
            return WarframeWeaponBuffResolver.resolve(selected, caster: caster,
                                                      configIndex: draft.configIndex)
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.availableExternalWarframes) { frame in
                        Button(frame.z) { model.setExternalCaster(frame.id, for: draft.id) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2")
                        Text(caster?.z ?? "选择施法者")
                        Image(systemName: "chevron.down")
                    }
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textPrimary)
                }
                .buttonStyle(.plain)
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { draft.active },
                    set: { model.setExternalWarframeBuffActive($0, for: draft.id) }
                ))
                .tint(WFTheme.gold)
                .font(.wfLabel)
                Button(role: .destructive) { model.removeExternalWarframeBuff(draft.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(WFTheme.red)
            }
            if caster == nil {
                Text("请选择另一名背包战甲作为外部施法者；当前战甲不能同时作为外部来源。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            } else if let caster {
                HStack(spacing: 6) {
                    Text("配置")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    ForEach(Array(caster.configs.enumerated()), id: \.element.id) { entry in
                        let index = entry.offset
                        Button(entry.element.label) {
                            model.setExternalCasterConfig(index, for: draft.id)
                        }
                        .font(.wfLabel)
                        .foregroundColor(index == draft.configIndex ? Color(hex: "1A1408") : WFTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(index == draft.configIndex ? WFTheme.gold : WFTheme.panelElevated))
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                if let config = caster.config(at: draft.configIndex), !config.isExactImport {
                    Text(config.issues.joined(separator: "\n"))
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.gold)
                }
            }
            if caster != nil, candidates.isEmpty {
                Text("这套施法者配置没有已接入、且能施加给队友的武器增益。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else if caster != nil {
                Menu {
                    ForEach(candidates) { candidate in
                        Button(candidate.name) {
                            model.setExternalWarframeBuffCandidate(candidate.id, for: draft.id)
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected?.name ?? "选择施放技能")
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textPrimary)
                            Text(selected?.detail ?? "只列出实际可给队友的技能")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                                .lineLimit(2)
                        }
                        Spacer()
                        if let preview {
                            Text(warframeBuffValueLabel(preview))
                                .font(.wfLabel)
                                .foregroundColor(draft.active ? WFTheme.gold : WFTheme.textMuted)
                                .multilineTextAlignment(.trailing)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(WFTheme.textMuted)
                    }
                    .padding(9)
                    .background(WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("同伴")
            Text("先选择账号快照中的同伴实例和 A/B/C 配置。只有该配置实际装配、且 DamageKit 已有精确满级作用值的同伴 Mod 才能进入本次结算。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            companionSelection
            if let companion = model.currentCompanion {
                companionConfiguration(companion)
                companionEffectControls
            } else {
                Text(model.availableCompanions.isEmpty
                     ? "当前账号快照没有可选同伴。"
                     : "未选择同伴；不会把任意同伴 Mod 当作已生效。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
        .wfCardStyle()
    }

    private var companionSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前同伴")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            if model.availableCompanions.isEmpty {
                Text("从军械库的账号快照进入计算器后，这里会列出已导入的同伴本体。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                Menu {
                    Button("不带同伴") { model.selectCurrentCompanion(nil) }
                    ForEach(model.availableCompanions) { companion in
                        Button(companion.z) { model.selectCurrentCompanion(companion.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pawprint.fill")
                            .foregroundColor(WFTheme.gold)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.currentCompanion?.z ?? "选择背包中的同伴")
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textPrimary)
                            Text(model.currentCompanion == nil
                                 ? "不带入同伴 Mod 或同伴赋能"
                                 : "使用它的 A/B/C 配置")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(WFTheme.textMuted)
                    }
                    .padding(10)
                    .background(WFUI.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func companionConfiguration(_ companion: InventoryData.OwnedEquipment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("同伴配置")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            if companion.configs.isEmpty {
                Text("账号快照没有这名同伴的 A/B/C 配置。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            } else {
                Picker("同伴配置", selection: Binding(
                    get: { model.currentCompanionConfigIndex },
                    set: { model.selectCurrentCompanionConfig($0) }
                )) {
                    ForEach(Array(companion.configs.enumerated()), id: \.offset) { index, config in
                        Text("配置 \(config.label)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
                if let config = model.currentCompanionConfig, !config.isExactImport {
                    ForEach(config.issues, id: \.self) { issue in
                        Text("• \(issue)")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }
                }
            }
        }
    }

    private var companionEffectControls: some View {
        let candidates = model.currentCompanionCandidates
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            Text("已装且会影响当前武器的同伴 Mod")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            Text("卡装上不等于战斗条件已经触发。开关只表示此刻条件成立；需要数值的条件仍须明确填写，0 不会自动当作满层。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            if candidates.isEmpty {
                Text("这套同伴配置没有已接入 DamageKit 的玩家武器增益 Mod。其他已导入的同伴 Mod 仍可在军械库配置页查看。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                ForEach(candidates) { candidate in
                    companionEffectRow(candidate)
                }
            }
        }
    }

    private func companionEffectRow(_ candidate: CompanionWeaponBuffCandidate) -> some View {
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: WFUI.s2) {
                if let mod = ModLibrary.shared.mod(named: candidate.modName) {
                    NativeThumb(local: model.catalog.localModIcon(for: mod),
                                remote: model.catalog.iconURL(for: mod), size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.catalog.local(candidate.modName))
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textPrimary)
                    Text("\(candidate.importedName) · 槽位 \(candidate.slot + 1) · \(candidate.rankLabel)")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Spacer(minLength: 0)
                if candidate.canCalculate {
                    Toggle("启用", isOn: Binding(
                        get: { model.activeCurrentCompanionBuffIDs.contains(candidate.id) },
                        set: { model.setCurrentCompanionBuff(candidate.id, active: $0) }
                    ))
                    .labelsHidden()
                    .tint(WFTheme.gold)
                }
            }
            Text(candidate.availability.detail)
                .font(.wfLabel)
                .foregroundColor(candidate.canCalculate ? WFTheme.textMuted : WFTheme.gold)
            if candidate.canCalculate, candidate.requiresConditionValue {
                DamageNumberField(
                    "条件值（0=未触发，1=已触发）",
                    value: companionConditionValue(candidate.id),
                    suffix: ""
                )
                .disabled(!model.activeCurrentCompanionBuffIDs.contains(candidate.id))
                .opacity(model.activeCurrentCompanionBuffIDs.contains(candidate.id) ? 1 : 0.48)
            } else if candidate.canCalculate {
                Text("启用开关表示这张同伴 Mod 的实际触发条件已满足。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func companionConditionValue(_ candidateID: String) -> Binding<Double> {
        Binding(
            get: { model.currentCompanionConditionValue(for: candidateID) },
            set: { model.setCurrentCompanionConditionValue($0, for: candidateID) }
        )
    }

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("外部环境")
            Text("这里放不属于武器、战甲或同伴的来源：网站的独立环境选项，或你明确知道数值的手动 Buff。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            scenarioEffectsControls(in: .environment, title: "环境选项")
            WFHairline()
            VStack(alignment: .leading, spacing: WFUI.s2) {
                HStack {
                    Text("手动 Buff").font(.wfBody).foregroundColor(WFTheme.textSecondary)
                    Spacer()
                    Button("添加") { model.addManualBuff() }
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.gold)
                }
                Text("只在来源没有可选的战甲或同伴 Mod 时使用。每一项都直接写出其提供的数值。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                ForEach(model.manualBuffs.indices, id: \.self) { index in
                    manualBuffEditor($model.manualBuffs[index])
                }
            }
        }
        .onChange(of: model.scenarioEffectDrafts) { _ in model.calculate() }
        .wfCardStyle()
    }

    @ViewBuilder
    private func scenarioEffectsControls(in group: NativeEffectGroup, title: String) -> some View {
        let indexes = model.scenarioEffectDrafts.indices.filter {
            model.scenarioEffectDrafts[$0].effect.nativeGroup == Optional(group)
        }
        if !indexes.isEmpty {
            VStack(alignment: .leading, spacing: WFUI.s2) {
                Text(title).font(.wfBody).foregroundColor(WFTheme.textSecondary)
                ForEach(indexes, id: \.self) { index in
                    let effect = model.scenarioEffectDrafts[index].effect
                    scenarioRow(
                        title: effect.nativeDisplayName,
                        detail: effect.nativeDisplayDetail,
                        enabled: $model.scenarioEffectDrafts[index].enabled,
                        value: effect.acceptsDisplayPercentage
                            ? $model.scenarioEffectDrafts[index].percent
                            : nil,
                        suffix: effect.nativeDisplayUnit
                    )
                }
            }
        }
    }

    private func scenarioRow(title: String, detail: String, enabled: Binding<Bool>,
                             value: Binding<Double>?, suffix: String) -> some View {
        HStack(alignment: .center, spacing: WFUI.s2) {
            Toggle("", isOn: enabled)
                .labelsHidden()
                .tint(WFTheme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textPrimary)
                Text(detail)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            Spacer(minLength: 0)
            if let value {
                DamageNumberField("", value: value, suffix: suffix)
                    .frame(width: 112)
                    .opacity(enabled.wrappedValue ? 1 : 0.48)
                    .disabled(!enabled.wrappedValue)
            } else {
                Text("开关")
                    .font(.wfLabel)
                    .foregroundColor(enabled.wrappedValue ? WFTheme.gold : WFTheme.textMuted)
                    .frame(width: 112, alignment: .trailing)
            }
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func manualBuffEditor(_ buff: Binding<NativeManualBuffDraft>) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            HStack {
                TextField("来源名称", text: buff.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) { model.removeManualBuff(buff.wrappedValue.id) } label: {
                    Image(systemName: "trash")
                }
                .foregroundColor(WFTheme.red)
            }
            HStack(spacing: WFUI.s2) {
                DamageNumberField("基础伤害", value: percent(buff.damageBonus), suffix: "%")
                DamageNumberField("暴击率", value: percent(buff.critChanceBonus), suffix: "%")
                DamageNumberField("暴伤", value: percent(buff.critDamageBonus), suffix: "%")
            }
            HStack(spacing: WFUI.s2) {
                DamageNumberField("多重", value: percent(buff.multishotBonus), suffix: "%")
                DamageNumberField("射速", value: percent(buff.fireRateBonus), suffix: "%")
                DamageNumberField("装填", value: percent(buff.reloadSpeedBonus), suffix: "%")
            }
            HStack(spacing: WFUI.s2) {
                DamageNumberField("状态率", value: percent(buff.statusChanceBonus), suffix: "%")
                DamageNumberField("状态时长", value: percent(buff.statusDurationBonus), suffix: "%")
            }
            HStack(spacing: WFUI.s2) {
                DamageNumberField("状态伤害", value: percent(buff.statusDamageBonus), suffix: "%")
                DamageNumberField("派系伤害", value: percent(buff.factionBonus), suffix: "%")
            }
            DisclosureGroup("额外元素与 DOT 伤害") {
                VStack(spacing: WFUI.s2) {
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("额外火", value: percent(buff.heatElementBonus), suffix: "%")
                        DamageNumberField("额外冰", value: percent(buff.coldElementBonus), suffix: "%")
                    }
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("额外电", value: percent(buff.electricityElementBonus), suffix: "%")
                        DamageNumberField("额外毒", value: percent(buff.toxinElementBonus), suffix: "%")
                    }
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("火 DOT", value: percent(buff.heatStatusDamageBonus), suffix: "%")
                        DamageNumberField("电 DOT", value: percent(buff.electricityStatusDamageBonus), suffix: "%")
                        DamageNumberField("毒 DOT", value: percent(buff.toxinStatusDamageBonus), suffix: "%")
                    }
                }
                .padding(.top, 6)
            }
            Toggle("启用", isOn: buff.active).tint(WFTheme.gold).font(.wfLabel)
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: buff.wrappedValue) { _ in model.calculate() }
    }

    private var advancedCard: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: WFUI.s3) {
                Toggle("潜行加成（仅近战）", isOn: $model.stealth).tint(WFTheme.gold)
                    .onChange(of: model.stealth) { _ in model.calculate() }
                if model.selectedWeaponIsMelee {
                    WFHairline()
                    Toggle("重击", isOn: $model.heavyAttack)
                        .tint(WFTheme.gold)
                        .onChange(of: model.heavyAttack) { _ in model.calculate() }
                    if model.heavyAttack {
                        DamageNumberField("重击起始连击", value: $model.heavyAttackStartingCombo,
                                          suffix: "x")
                            .onChange(of: model.heavyAttackStartingCombo) { _ in model.calculate() }
                    }
                    Toggle("轻击连击倍率", isOn: $model.meleeComboEnabled)
                        .tint(WFTheme.gold)
                        .onChange(of: model.meleeComboEnabled) { _ in model.calculate() }
                    if model.meleeComboEnabled {
                        DamageNumberField("轻击连击倍率", value: $model.meleeComboMultiplier,
                                          suffix: "x")
                            .onChange(of: model.meleeComboMultiplier) { _ in model.calculate() }
                    }
                    Text("与网站同名选项一致：重击的动作、起手与消耗由 DamageKit 根据武器和 Mod 原始数据计算；轻击倍率只供按连击结算的 Mod 使用。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                if model.selectedWeaponIsExalted {
                    WFHairline()
                    Toggle("技能连击倍率", isOn: $model.abilityComboEnabled)
                        .tint(WFTheme.gold)
                        .onChange(of: model.abilityComboEnabled) { _ in model.calculate() }
                    if model.abilityComboEnabled {
                        DamageNumberField("技能连击倍率", value: $model.abilityComboMultiplier, suffix: "x")
                            .onChange(of: model.abilityComboMultiplier) { _ in model.calculate() }
                    }
                    Text("仅对武器数据标为 Exalted Weapon 的攻击生效；它和网站同名自定义属性同时存在时，由 DamageKit 取两者较大值。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                if model.selectedWeaponHasSniperCombo {
                    WFHairline()
                    Toggle("狙击连击倍率（覆盖默认 1.5x）", isOn: $model.sniperComboEnabled)
                        .tint(WFTheme.gold)
                        .onChange(of: model.sniperComboEnabled) { _ in model.calculate() }
                    if model.sniperComboEnabled {
                        DamageNumberField("狙击连击倍率", value: $model.sniperComboMultiplier, suffix: "x")
                            .onChange(of: model.sniperComboMultiplier) { _ in model.calculate() }
                    }
                    Text("仅带 sniperCombo 标记的瞄准攻击段读取该值；关闭覆盖时仍采用网站的固有 1.5x。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Toggle("爆头", isOn: $model.headshot).tint(WFTheme.gold)
                Toggle("弱点命中（Acuity 等）", isOn: $model.weakPoint).tint(WFTheme.gold)
                HStack(spacing: WFUI.s2) {
                    DamageNumberField("距离", value: distanceBinding, suffix: "m")
                    DamageNumberField("时长", value: $model.window, suffix: "秒")
                }
                Text("腐蚀层数上限由当前战甲实际装配的执政官石计算。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                HStack(spacing: WFUI.s2) {
                    DamageNumberField("预置腐蚀", value: statusBinding("corrosive"), suffix: "层")
                    DamageNumberField("预置热", value: statusBinding("heat"), suffix: "层")
                    DamageNumberField("预置磁", value: statusBinding("magnetic"), suffix: "层")
                }
                Toggle("手动指定目标状态种类数", isOn: $model.manualStatusCountEnabled)
                    .tint(WFTheme.gold)
                    .onChange(of: model.manualStatusCountEnabled) { _ in model.calculate() }
                if model.manualStatusCountEnabled {
                    DamageNumberField("状态种类数", value: $model.manualStatusCount, suffix: "种")
                        .onChange(of: model.manualStatusCount) { _ in model.calculate() }
                    Text("此项与 warframe-damage 一样，只覆盖 Condition Overload / Gun CO 的状态种类计数；不会虚构病毒、腐蚀或外部 DOT。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Toggle("每种状态伤害按乘法结算", isOn: $model.forceMultiplicativePerStatusDamage)
                    .tint(WFTheme.gold)
                    .onChange(of: model.forceMultiplicativePerStatusDamage) { _ in model.calculate() }
                Text("对应网站的“Damage per status multiplier is multiplicative”。它只改变 Gun CO / Condition Overload 的乘区，不会自行增加状态层数。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                customStatControls
                Text("预置状态表示射击前已存在的目标状态；不会虚构外部 DOT 伤害。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            .padding(.top, WFUI.s2)
        } label: {
            Text("高级目标与状态选项")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
        }
        .tint(WFTheme.gold)
        .wfCardStyle()
    }

    private var customStatControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: WFUI.s3) {
                Text("数值、单位和顺序与网站 customStats 面板对应；百分号字段输入 50 就是 +50%。这里的输入只传数据，实际结算仍由 DamageKit 统一完成。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)

                customStatSection("基础与每状态") {
                    HStack(spacing: WFUI.s2) {
                        customStatField(.base, "基础伤害")
                        customStatField(.basePerStatus, "每种状态伤害")
                        customStatField(.flatChangeDamage, "固定基础伤害", suffix: "")
                    }
                }
                customStatSection("暴击") {
                    HStack(spacing: WFUI.s2) {
                        customStatField(.critChance, "暴击率")
                        customStatField(.multiplicativeCritChance, "暴击率乘算")
                        customStatField(.flatCritChance, "暴击率绝对")
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.weakPointCritChance, "弱点暴击率")
                        customStatField(.critMultiplier, "暴击倍率")
                        customStatField(.flatCritMultiplier, "暴伤绝对", suffix: "x")
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.finalCritMultiplier, "暴伤最终乘算", suffix: "")
                        Spacer()
                        Spacer()
                    }
                }
                customStatSection("状态") {
                    HStack(spacing: WFUI.s2) {
                        customStatField(.statusChance, "状态率")
                        customStatField(.statusChanceMultiplier, "状态率易伤")
                        customStatField(.absoluteStatusChance, "状态率绝对", suffix: "pp")
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.statusDamage, "状态伤害")
                        customStatField(.vulnerableStatusDamage, "状态伤害易伤")
                        Spacer()
                    }
                }
                customStatSection("武器与弱点") {
                    HStack(spacing: WFUI.s2) {
                        customStatField(.speed, "射速 / 攻速")
                        customStatField(.multishot, "多重", suffix: "")
                        customStatField(.magazineSize, "弹匣")
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.reloadTime, "装填")
                        customStatField(.headshotDamage, "爆头伤害")
                        customStatField(.weakPointDamage, "弱点伤害")
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.damageVulnerability, "伤害易伤")
                        Spacer()
                        Spacer()
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.abilityCombo, "技能连击", suffix: "x")
                        customStatField(.initialCombo, "初始连击", suffix: "")
                        customStatField(.heatAdd, "附加火焰实例")
                    }
                    HStack(spacing: WFUI.s2) {
                        customStatField(.heatInherit, "火焰继承")
                        Spacer()
                        Spacer()
                    }
                    Text("“附加火焰实例”对应网站 heatAdd：作为独立火元素直击加入，不参与武器槽位的元素合成；火焰状态也读取同一加成。“火焰继承”只覆盖火 DOT 的元素加成，不改变直击。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
            }
            .padding(.top, WFUI.s2)
        } label: {
            Text("网站自定义属性")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
        }
        .tint(WFTheme.gold)
    }

    @ViewBuilder
    private func customStatSection<Content: View>(_ title: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Text(title)
                .font(.wfLabel)
                .foregroundColor(WFTheme.gold)
            content()
        }
    }

    private func customStatField(_ key: CustomStatKey, _ title: String,
                                 suffix: String? = nil) -> some View {
        DamageNumberField(title, value: customStatBinding(key),
                          suffix: suffix ?? (key.usesPercentInput ? "%" : ""))
    }

    private var calculationButton: some View {
        Button { model.calculate() } label: {
            HStack {
                Spacer()
                if model.calculating { ProgressView().tint(WFTheme.bgPrimary) }
                Text(model.calculating ? "计算中…" : "计算伤害")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundColor(WFTheme.bgPrimary)
            .padding(.vertical, 13)
            .background(WFTheme.gold)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(model.selectedWeapon == nil || model.selectedEnemy == nil || model.calculating)
        .opacity(model.selectedWeapon == nil || model.selectedEnemy == nil ? 0.5 : 1)
    }

    @ViewBuilder
    private var resultsCard: some View {
        if let error = model.calculationError {
            problemCard(error)
        }
        if let result = model.result {
            VStack(alignment: .leading, spacing: WFUI.s3) {
                WFSectionHeader("结果", trailing: "\(result.window.cleanNumber) 秒窗口")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WFUI.s2), count: 2),
                          spacing: WFUI.s2) {
                    resultStat("生命", result.enemyStats.health)
                    resultStat("护甲", result.enemyStats.armor)
                    resultStat("护盾", result.enemyStats.shield)
                    resultStat("超宏", result.enemyStats.overguard)
                }
                ForEach(Array(result.attacks.enumerated()), id: \.offset) { index, attack in
                    if index > 0 { WFHairline() }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(attack.attack).font(.wfTitle).foregroundColor(WFTheme.textPrimary)
                        HStack {
                            resultMetric("武器 DPS", attack.dps, accent: WFTheme.gold)
                            Spacer()
                            resultMetric("连续期望直击 DPS", attack.targetDirectDps, accent: WFTheme.cyan)
                        }
                        HStack {
                            resultMetric("连续期望总 DPS", attack.targetDps, accent: WFTheme.cyan)
                            Spacer()
                        }
                        Text("前两项是完整时间窗内的连续期望值：直击栏不混入 DOT，总 DPS 包含 DOT；它们不等同于网站的随机队列中位数。")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                        HStack {
                            Text("直伤 \(compact(attack.directDamage))")
                            Text("DOT \(compact(attack.dotDamage))")
                            Text("射击 \(attack.shots.cleanNumber)")
                        }
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WFUI.s2), count: 2),
                                  spacing: WFUI.s2) {
                            resultMetric("目标直击总量", attack.targetDirectDamage, accent: WFTheme.cyan)
                            resultMetric("目标 DOT 总量", attack.targetDotDamage, accent: WFTheme.cyan)
                        }
                        resultDamageTypeBreakdown(attack.targetByType)
                        resultLayerBreakdown(attack.layers)
                        resultProcBreakdown(attack.procs)
                        if !attack.notes.isEmpty {
                            Text(attack.notes.joined(separator: " · "))
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.red)
                        }
                    }
                }
                if !result.notes.isEmpty {
                    Text(result.notes.joined(separator: "\n"))
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                }
            }
            .wfCardStyle(isHighlighted: true)
        } else if model.selectedWeapon != nil {
            WFCard {
                Text("配置完成后点“计算伤害”查看每段攻击的直伤、DOT、目标 DPS 与时间线诊断。")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
    }

    private func selectionRow(title: String, primary: String, secondary: String,
                              image: URL?, remote: URL?) -> some View {
        HStack(spacing: WFUI.s3) {
            NativeThumb(local: image, remote: remote, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.wfLabel).foregroundColor(WFTheme.textMuted)
                Text(primary).font(.wfTitle).foregroundColor(WFTheme.textPrimary).lineLimit(1)
                Text(secondary).font(.wfLabel).foregroundColor(WFTheme.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(WFTheme.textMuted)
        }
        .contentShape(Rectangle())
    }

    private func resultStat(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.wfLabel).foregroundColor(WFTheme.textMuted)
            Text(compact(value)).font(.wfNumSmall).foregroundColor(WFTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func resultMetric(_ title: String, _ value: Double, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.wfLabel).foregroundColor(WFTheme.textMuted)
            Text(compact(value)).font(.wfNum).foregroundColor(accent)
        }
    }

    @ViewBuilder
    private func resultDamageTypeBreakdown(_ values: [String: Double]) -> some View {
        let rows = values
            .filter { abs($0.value) > .ulpOfOne }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("目标伤害构成")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                          spacing: 6) {
                    ForEach(rows, id: \.key) { row in
                        Text("\(localizedDamageType(row.key)) \(compact(row.value))")
                            .font(.wfLabel.monospacedDigit())
                            .foregroundColor(WFTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(WFUI.raised)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultLayerBreakdown(_ layers: [LayerResult]) -> some View {
        if !layers.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("目标层明细")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(layer.layer.zhName)
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textPrimary)
                            Spacer()
                            Text("层生命 \(compact(layer.maxHP))")
                        }
                        HStack(spacing: WFUI.s2) {
                            Text("承伤 \(compact(layer.damage))")
                            Text("DPS \(compact(layer.dps))")
                            Spacer()
                            if let ttk = layer.ttk {
                                Text("击杀 \(ttk.cleanNumber)s")
                            } else {
                                Text("窗口内未击杀")
                            }
                        }
                    }
                    .font(.wfLabel.monospacedDigit())
                    .foregroundColor(WFTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func resultProcBreakdown(_ procs: [String: Double]) -> some View {
        let rows = procs
            .filter { abs($0.value) > .ulpOfOne }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        if !rows.isEmpty {
            Text("预期状态：\(rows.map { "\(localizedDamageType($0.key)) \(compact($0.value))" }.joined(separator: " · "))")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textSecondary)
        }
    }

    private func localizedDamageType(_ key: String) -> String {
        switch key.lowercased() {
        case "impact": return "冲击"
        case "puncture": return "穿刺"
        case "slash": return "切割"
        case "heat", "ignite": return "火焰"
        case "cold": return "冰冻"
        case "electricity": return "电击"
        case "toxin": return "毒素"
        case "blast", "detonate": return "爆炸"
        case "gas": return "毒气"
        case "radiation": return "辐射"
        case "magnetic": return "磁力"
        case "viral": return "病毒"
        case "corrosive": return "腐蚀"
        case "void": return "虚空"
        default:
            let titleCase = key.prefix(1).uppercased() + key.dropFirst()
            return model.catalog.local(titleCase)
        }
    }

    private var selectedWeaponEntry: NativeDamageWeaponEntry? {
        model.catalog.weapons.first { $0.n == model.weaponName }
    }

    private var selectedWeaponLabel: String {
        selectedWeaponEntry?.z ?? model.weaponName.map(model.catalog.local) ?? "选择武器"
    }

    private var selectedWeaponDetail: String {
        guard let entry = selectedWeaponEntry else { return "支持中英文搜索、图片与分类" }
        return "\(entry.n) · \(entry.categoryLabel) · \(entry.atk.count) 段攻击"
    }

    private var selectedEnemyLabel: String {
        model.enemyName.map(model.catalog.local) ?? "选择敌人"
    }

    private var selectedEnemyDetail: String {
        guard let enemy = model.selectedEnemy else { return "支持中英文搜索" }
        return "\(enemy.name) · \(enemy.faction)"
    }

    private var distanceBinding: Binding<Double> {
        Binding(get: { model.distance ?? 0 }, set: { model.distance = $0 > 0 ? $0 : nil })
    }

    private func stackBinding(_ rule: ConditionalEffectRule) -> Binding<Double> {
        Binding(get: { model.conditionalStacks[rule.mod] ?? 0 }, set: { model.setStack($0, for: rule) })
    }

    private var allConditionsBinding: Binding<Bool> {
        Binding(get: { model.allWeaponConditionsMaxed }, set: { model.setAllWeaponConditionsMaxed($0) })
    }

    private var rivenSlotBinding: Binding<Int?> {
        Binding(get: { model.riven.slot }, set: { model.setRivenSlot($0) })
    }

    private func rivenStatBinding(_ stat: NativeRivenStat) -> Binding<Double> {
        Binding(get: { model.riven.value(for: stat) }, set: { model.setRivenValue($0, for: stat) })
    }

    private var stanceComboBinding: Binding<String> {
        Binding(
            get: { model.stanceCombo ?? model.availableStanceCombos.first?.name ?? "" },
            set: { model.setStanceCombo($0) }
        )
    }

    private func attackCombinationBinding(_ group: [Int]) -> Binding<Bool> {
        Binding(get: { model.isAttackCombinationSelected(group) }, set: {
            model.setAttackCombination(group, selected: $0)
        })
    }

    private func statusBinding(_ type: String) -> Binding<Double> {
        Binding(get: { model.initialStatusStacks[type] ?? 0 }, set: { model.setInitialStatus(type, stacks: $0) })
    }

    private func customStatBinding(_ key: CustomStatKey) -> Binding<Double> {
        Binding(get: { model.customStatInputValue(key) }, set: {
            model.setCustomStatInput($0, for: key)
        })
    }

    private func currentWarframeBuffBinding(_ candidateID: String) -> Binding<Bool> {
        Binding(
            get: { model.activeCurrentWarframeBuffIDs.contains(candidateID) },
            set: { model.setCurrentWarframeBuff(candidateID, active: $0) }
        )
    }

    private func warframeBuffValueLabel(_ resolution: WarframeWeaponBuffResolution) -> String {
        switch resolution.candidate.route {
        case .scenario:
            let value = resolution.finalPercent ?? 0
            return String(format: "结算值 +%.1f%%\n施法强度 %d%%", value, resolution.strength.percent)
        case let .externalMod(_, rankScale):
            let value = rankScale * resolution.strength.multiplier * 100
            return String(format: "附伤 +%.1f%%\n施法强度 %d%%", value, resolution.strength.percent)
        }
    }

    private func percent(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 })
    }

    private func incarnonBinding(_ tier: Int) -> Binding<Int> {
        Binding(get: { model.incarnonSelections[tier] ?? 0 }, set: {
            model.setIncarnonSelection(tier, index: $0)
        })
    }

    private func slotLabel(_ slot: Int) -> String {
        switch slot {
        case 0...7: return "Mod \(slot + 1)"
        case 8: return "功能槽"
        case 9: return "架势"
        default: return "武器赋能"
        }
    }

    private func compact(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000_000...: return String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000...: return String(format: "%.2fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fk", value / 1_000)
        default: return String(format: value.rounded() == value ? "%.0f" : "%.2f", value)
        }
    }
}

private struct DamageNumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String
    let allowsNegative: Bool

    init(_ title: String, value: Binding<Double>, suffix: String, allowsNegative: Bool = false) {
        self.title = title
        _value = value
        self.suffix = suffix
        self.allowsNegative = allowsNegative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.wfLabel).foregroundColor(WFTheme.textMuted)
            HStack(spacing: 3) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                    .font(.wfBody.monospacedDigit())
                    .foregroundColor(WFTheme.textPrimary)
                if !suffix.isEmpty {
                    Text(suffix).font(.wfLabel).foregroundColor(WFTheme.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(WFUI.raised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeThumb: View {
    let local: URL?
    let remote: URL?
    let size: CGFloat

    @ViewBuilder
    private var image: some View {
        // `AsyncImage` is meant for URL loading and is not a dependable way to
        // render a file URL from the app bundle.  The generated DamageData
        // folder deliberately contains local WebP thumbnails so the picker is
        // usable offline; read those through UIKit first and use the upstream
        // URL only for a genuinely missing cached icon.
#if canImport(UIKit)
        if let local, let uiImage = UIImage(contentsOfFile: local.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            remoteImage
        }
#else
        remoteImage
#endif
    }

    @ViewBuilder
    private var remoteImage: some View {
        if let remote {
            AsyncImage(url: remote) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "scope")
            .font(.system(size: size * 0.34, weight: .light))
            .foregroundColor(WFTheme.textMuted)
    }

    var body: some View {
        image
        .frame(width: size, height: size)
        .background(WFTheme.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NativeWeaponPicker: View {
    @ObservedObject var model: NativeDamageCalculatorModel
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [NativeDamageWeaponEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return model.catalog.weapons }
        return model.catalog.weapons.filter {
            $0.n.lowercased().contains(term) || $0.z.lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List(rows) { weapon in
                Button {
                    select(weapon.n)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        NativeThumb(local: model.catalog.localWeaponIcon(named: weapon.img), remote: weapon.iconURL, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(weapon.z).foregroundColor(WFTheme.textPrimary)
                            Text("\(weapon.n) · \(weapon.categoryLabel)")
                                .font(.wfLabel).foregroundColor(WFTheme.textSecondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WFTheme.bgPrimary)
            .searchable(text: $query, prompt: "搜索武器（中英文）")
            .navigationTitle("选择武器")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NativeEnemyPicker: View {
    @ObservedObject var model: NativeDamageCalculatorModel
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [Enemy] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return model.catalog.enemies }
        return model.catalog.enemies.filter {
            $0.name.lowercased().contains(term) || model.catalog.local($0.name).lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List(rows, id: \.name) { enemy in
                Button {
                    select(enemy.name)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.catalog.local(enemy.name)).foregroundColor(WFTheme.textPrimary)
                        Text("\(enemy.name) · \(enemy.faction)")
                            .font(.wfLabel).foregroundColor(WFTheme.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WFTheme.bgPrimary)
            .searchable(text: $query, prompt: "搜索敌人（中英文）")
            .navigationTitle("选择敌人")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NativeModPicker: View {
    @ObservedObject var model: NativeDamageCalculatorModel
    let slot: Int
    let select: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [ModDefinition] {
        guard let weapon = model.selectedWeapon else { return [] }
        let used = Set(model.weaponSlots.enumerated().compactMap { $0.offset == slot ? nil : $0.element })
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ModLibrary.shared.definitions.filter { mod in
            guard !used.contains(mod.name), model.catalog.accepts(mod, weapon: weapon), matchesSlot(mod) else { return false }
            return term.isEmpty || mod.name.lowercased().contains(term) || model.catalog.local(mod.name).lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button(role: .destructive) {
                    select(nil)
                    dismiss()
                } label: { Label("卸下此槽位", systemImage: "xmark.circle") }
                ForEach(rows, id: \.name) { mod in
                    Button {
                        select(mod.name)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            NativeThumb(local: model.catalog.localModIcon(for: mod),
                                        remote: model.catalog.iconURL(for: mod), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.catalog.local(mod.name)).foregroundColor(WFTheme.textPrimary)
                                Text(mod.name).font(.wfLabel).foregroundColor(WFTheme.textSecondary)
                                if let info = mod.info, !info.isEmpty {
                                    Text(info).font(.wfLabel).foregroundColor(WFTheme.textMuted).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WFTheme.bgPrimary)
            .searchable(text: $query, prompt: "搜索 Mod（中英文）")
            .navigationTitle("选择 \(slotTitle)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private var slotTitle: String {
        switch slot {
        case 8: return "功能槽"
        case 9: return "架势"
        case 10: return "武器赋能"
        default: return "Mod 槽"
        }
    }

    private func matchesSlot(_ mod: ModDefinition) -> Bool {
        let type = (mod.type ?? "").lowercased()
        if slot == 9 { return type == "stance" }
        // 网站原始数据把武器 Arcane 标为 weapon_mist（不是 arcane）；
        // 例如 Cascadia Flare、Primary Merciless。接受旧别名只是兼容数据，
        // 不把它们误放入普通八个 Mod 槽。
        if slot == 10 { return type == "weapon_mist" || type == "arcane" }
        if slot == 8 { return type == "exilus" || type.isEmpty }
        return type != "stance" && type != "arcane" && type != "weapon_mist"
            && type != "aura" && !type.contains("frame") && type != "shard"
    }
}

private extension Double {
    var cleanNumber: String {
        rounded() == self ? String(format: "%.0f", self) : String(format: "%.2f", self)
    }
}
