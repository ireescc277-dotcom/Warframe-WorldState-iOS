import SwiftUI
import DamageKit
#if canImport(UIKit)
import UIKit
#endif

private enum NativeCalcSheet: Identifiable {
    case weapon
    case enemy
    case mod(slot: Int)
    case shard(slot: Int)
    case effect(group: NativeEffectGroup)

    var id: String {
        switch self {
        case .weapon: return "weapon"
        case .enemy: return "enemy"
        case .mod(let slot): return "mod-\(slot)"
        case .shard(let slot): return "shard-\(slot)"
        case .effect(let group): return "effect-\(group.rawValue)"
        }
    }
}

private extension ScenarioEffectID {
    var nativeDisplayName: String {
        switch self {
        case .roar: return "Roar（Rhino）"
        case .eclipse: return "Eclipse（Mirage）"
        case .nourish: return "Nourish（Grendel）"
        case .xata: return "Xata's Whisper（虚空低语）"
        case .toxicLash: return "Toxic Lash（毒鞭）"
        case .flatCriticalChance: return "绝对暴击率"
        case .madurai: return "Madurai"
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
    private let resultsAnchor = "native-damage-results"

    init(weapon: String? = nil, title: String = "伤害计算") {
        self.title = title
        _model = StateObject(wrappedValue: NativeDamageCalculatorModel(initialWeaponName: weapon))
        autoRevealResults = CommandLine.arguments.contains("-calcResult")
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
                            environmentCard
                            scenarioCard
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
            case .shard(let slot):
                NativeShardPicker(model: model, slot: slot) { name in
                    model.setArchonShard(name, in: slot)
                    sheet = nil
                }
            case .effect(let group):
                NativeEffectPicker(model: model, group: group) { name in
                    model.addExternalMod(name, to: group)
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
                Text("原生 Swift · 与网站配置逐例对拍")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
            }
            Spacer()
            if model.calculating {
                ProgressView().tint(WFTheme.gold)
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
                archonShardControls
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
            Toggle("启用紫卡（手动最终词条）", isOn: $model.riven.enabled)
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
            VStack(spacing: WFUI.s2) {
                    TextField("紫卡名称", text: $model.riven.name)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("伤害", value: $model.riven.damagePercent, suffix: "%")
                        DamageNumberField("多重", value: $model.riven.multishotPercent, suffix: "%")
                    }
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("暴击率", value: $model.riven.critChancePercent, suffix: "%")
                        DamageNumberField("暴伤", value: $model.riven.critDamagePercent, suffix: "%")
                    }
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("状态率", value: $model.riven.statusChancePercent, suffix: "%")
                        DamageNumberField("状态时长", value: $model.riven.statusDurationPercent, suffix: "%")
                    }
                    HStack(spacing: WFUI.s2) {
                        DamageNumberField("射速", value: $model.riven.fireRatePercent, suffix: "%")
                        DamageNumberField("装填", value: $model.riven.reloadSpeedPercent, suffix: "%")
                        DamageNumberField("派系", value: $model.riven.factionPercent, suffix: "%")
                    }
                    DisclosureGroup("元素、物理与派系词条") {
                        VStack(spacing: WFUI.s2) {
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("火", value: $model.riven.heatPercent, suffix: "%")
                                DamageNumberField("冰", value: $model.riven.coldPercent, suffix: "%")
                            }
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("电", value: $model.riven.electricityPercent, suffix: "%")
                                DamageNumberField("毒", value: $model.riven.toxinPercent, suffix: "%")
                            }
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("冲击", value: $model.riven.impactPercent, suffix: "%")
                                DamageNumberField("穿刺", value: $model.riven.puncturePercent, suffix: "%")
                                DamageNumberField("切割", value: $model.riven.slashPercent, suffix: "%")
                            }
                            Text("组合元素（按紫卡所在 Mod 槽进入伤害向量）")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("病毒", value: $model.riven.viralPercent, suffix: "%")
                                DamageNumberField("腐蚀", value: $model.riven.corrosivePercent, suffix: "%")
                                DamageNumberField("辐射", value: $model.riven.radiationPercent, suffix: "%")
                            }
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("磁力", value: $model.riven.magneticPercent, suffix: "%")
                                DamageNumberField("毒气", value: $model.riven.gasPercent, suffix: "%")
                                DamageNumberField("爆炸", value: $model.riven.blastPercent, suffix: "%")
                            }
                            Text("派系伤害")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("Grineer", value: $model.riven.grineerFactionPercent, suffix: "%")
                                DamageNumberField("Corpus", value: $model.riven.corpusFactionPercent, suffix: "%")
                            }
                            HStack(spacing: WFUI.s2) {
                                DamageNumberField("Infested", value: $model.riven.infestedFactionPercent, suffix: "%")
                                DamageNumberField("Orokin", value: $model.riven.orokinFactionPercent, suffix: "%")
                            }
                        }
                        .padding(.top, 6)
                    }
                    Text("紫卡会占用这个槽位；元素词条也按该槽位参与合成。这里填写最终数值：60 表示 +60%，不会重复套 disposition。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
            }
        }
        .onChange(of: model.riven) { _ in model.calculate() }
    }

    private var archonShardControls: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("执政官石")
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textSecondary)
                    Text("五个独立槽位；石头效果由所选卡片的原始 action 进入计算。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WFUI.s2) {
                ForEach(model.archonShardSlots.indices, id: \.self) { slot in
                    Button { sheet = .shard(slot: slot) } label: {
                        archonShardSlot(slot)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, WFUI.s2)
    }

    private func archonShardSlot(_ slot: Int) -> some View {
        let selected = model.archonShardSlots[slot]
        return HStack(spacing: 8) {
            if let selected, let mod = ModLibrary.shared.mod(named: selected) {
                NativeThumb(local: model.catalog.localModIcon(for: mod),
                            remote: model.catalog.iconURL(for: mod), size: 30)
            } else {
                Image(systemName: "diamond")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
                    .frame(width: 30, height: 30)
                    .background(WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("石槽 \(slot + 1)")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                Text(selected.map(model.catalog.local) ?? "选择执政官石")
                    .font(.wfBody)
                    .foregroundColor(selected == nil ? WFTheme.textSecondary : WFTheme.textPrimary)
                    .lineLimit(1)
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
                            Text(option.name.isEmpty ? "选项 \(index + 1)" : option.name).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WFTheme.gold)
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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.catalog.local(rule.mod))
                                    .font(.wfBody)
                                    .foregroundColor(WFTheme.textPrimary)
                                Text("\(rule.maxStacks.cleanNumber) 层上限 · \(rule.mode == .totalRelativeToStaticAction ? "满层总值插值" : "满层额外值")")
                                    .font(.wfLabel)
                                    .foregroundColor(WFTheme.textMuted)
                            }
                            Spacer()
                            Stepper(value: stackBinding(rule), in: 0...rule.maxStacks, step: 1) {
                                Text("\((model.conditionalStacks[rule.mod] ?? 0).cleanNumber) 层")
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

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("战甲、同伴与环境")
            HStack(spacing: WFUI.s2) {
                DamageNumberField("技能强度（全局）", value: $model.abilityStrengthPercent, suffix: "%")
            }
            .onChange(of: model.abilityStrengthPercent) { _ in model.calculate() }
            Text("对应 warframe-damage 的全局 Strength：所有标记为随技能强度缩放的战甲、同伴和武器数据共用这一项。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            ForEach(NativeEffectGroup.allCases) { group in
                VStack(alignment: .leading, spacing: WFUI.s2) {
                    HStack {
                        Text(group.title).font(.wfBody).foregroundColor(WFTheme.textSecondary)
                        Spacer()
                        Button("添加") { sheet = .effect(group: group) }
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }
                    ForEach(model.externalEffects.indices, id: \.self) { index in
                        let effect = $model.externalEffects[index]
                        if effect.wrappedValue.group == group {
                            externalEffectRow(effect)
                        }
                    }
                }
                if group != NativeEffectGroup.allCases.last { WFHairline() }
            }
            VStack(alignment: .leading, spacing: WFUI.s2) {
                HStack {
                    Text("任意手动 Buff").font(.wfBody).foregroundColor(WFTheme.textSecondary)
                    Spacer()
                    Button("添加") { model.addManualBuff() }
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.gold)
                }
                ForEach(model.manualBuffs.indices, id: \.self) { index in
                    manualBuffEditor($model.manualBuffs[index])
                }
            }
        }
        .wfCardStyle()
    }

    /// The website has a separate environment-options panel in addition to
    /// Mod/companion sources. Keep named effects here so a user does not have
    /// to translate Roar, Nourish, or flat critical chance into a made-up Mod.
    private var scenarioCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("网站环境选项", trailing: "逐例对拍")
            Text("这些不是手动 Buff 的别名：它们按网站同名选项的结算位置传给 DamageKit。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            ForEach(model.scenarioEffectDrafts.indices, id: \.self) { index in
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
        .onChange(of: model.scenarioEffectDrafts) { _ in model.calculate() }
        .wfCardStyle()
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

    private func externalEffectRow(_ effect: Binding<NativeEffectDraft>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if let mod = ModLibrary.shared.mod(named: effect.wrappedValue.modName) {
                    NativeThumb(local: model.catalog.localModIcon(for: mod),
                                remote: model.catalog.iconURL(for: mod), size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.catalog.local(effect.wrappedValue.modName))
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textPrimary)
                    Text(effect.wrappedValue.modName)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Spacer()
                Toggle("", isOn: effect.active)
                    .labelsHidden()
                    .tint(WFTheme.gold)
                Button(role: .destructive) { model.removeExternalEffect(effect.wrappedValue.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(WFTheme.red)
            }
            DamageNumberField("条件值（0=未满足）", value: conditionValue(effect), suffix: "")
        }
        .padding(10)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: effect.wrappedValue) { _ in model.calculate() }
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
                Text("腐蚀层数上限由上方五个执政官石槽中的实际石头卡计算。")
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

    private func conditionValue(_ effect: Binding<NativeEffectDraft>) -> Binding<Double> {
        Binding(get: { effect.wrappedValue.conditionValue ?? 0 }, set: {
            effect.wrappedValue.conditionValue = $0 > 0 ? $0 : nil
        })
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

    init(_ title: String, value: Binding<Double>, suffix: String) {
        self.title = title
        _value = value
        self.suffix = suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.wfLabel).foregroundColor(WFTheme.textMuted)
            HStack(spacing: 3) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
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

private struct NativeShardPicker: View {
    @ObservedObject var model: NativeDamageCalculatorModel
    let slot: Int
    let select: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [ModDefinition] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ModLibrary.shared.definitions.filter { mod in
            guard mod.type?.lowercased() == "shard" else { return false }
            return term.isEmpty || mod.name.lowercased().contains(term)
                || model.catalog.local(mod.name).lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button(role: .destructive) {
                    select(nil)
                    dismiss()
                } label: {
                    Label("清空此石槽", systemImage: "xmark.circle")
                }
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
            .searchable(text: $query, prompt: "搜索执政官石（中英文）")
            .navigationTitle("选择石槽 \(slot + 1)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NativeEffectPicker: View {
    @ObservedObject var model: NativeDamageCalculatorModel
    let group: NativeEffectGroup
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [ModDefinition] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ModLibrary.shared.definitions.filter { mod in
            guard matchesGroup(mod) else { return false }
            return term.isEmpty || mod.name.lowercased().contains(term) || model.catalog.local(mod.name).lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List(rows, id: \.name) { mod in
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
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WFTheme.bgPrimary)
            .searchable(text: $query, prompt: "搜索 Mod（中英文）")
            .navigationTitle(group.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func matchesGroup(_ mod: ModDefinition) -> Bool {
        let type = (mod.type ?? "").lowercased()
        let tags = Set((mod.tags ?? []).map { $0.lowercased() })
        switch group {
        case .warframe:
            return type.contains("frame") || ["aura", "shard"].contains(type)
        case .companion:
            return type.contains("companion") || tags.contains("companion") || tags.contains("sentinel") || tags.contains("beast")
        case .environment:
            return true
        }
    }
}

private extension Double {
    var cleanNumber: String {
        rounded() == self ? String(format: "%.0f", self) : String(format: "%.2f", self)
    }
}
