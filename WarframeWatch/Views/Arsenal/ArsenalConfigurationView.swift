import SwiftUI

/// The intermediate Arsenal screen between an owned item and the calculator.
///
/// A weapon row is an account instance, not a generic weapon definition.  This
/// screen makes the player choose and inspect that instance's A/B/C build (and
/// the current Warframe build) before a calculation can begin.  It keeps the
/// navigation contract close to the game's Arsenal: choose a configuration
/// first; simulate it second.
struct ArsenalWeaponConfigurationView: View {
    let ownedWeapon: InventoryData.OwnedWeapon
    let availableWarframes: [InventoryData.OwnedWarframe]
    /// The Arsenal list verifies this against the bundled calculator catalogue.
    /// Keeping it separate from `calcName != nil` avoids offering a button for
    /// an instance whose static definition is not actually in this app build.
    private let calculatorAvailable: Bool

    @State private var weaponConfigIndex: Int
    @State private var currentWarframeID: String?
    @State private var currentWarframeConfigIndex: Int
    @State private var openCalculator = false

    init(ownedWeapon: InventoryData.OwnedWeapon,
         availableWarframes: [InventoryData.OwnedWarframe],
         initialWeaponConfigIndex: Int = 0,
         initialWarframe: InventoryData.OwnedWarframe? = nil,
         initialWarframeConfigIndex: Int = 0,
         calculatorAvailable: Bool? = nil) {
        self.ownedWeapon = ownedWeapon
        self.calculatorAvailable = calculatorAvailable ?? (ownedWeapon.calcName != nil)

        var frames = availableWarframes
        if let initialWarframe,
           !frames.contains(where: { $0.id == initialWarframe.id }) {
            frames.append(initialWarframe)
        }
        self.availableWarframes = frames.sorted {
            $0.z.localizedStandardCompare($1.z) == .orderedAscending
        }

        let safeWeaponConfig = min(
            max(initialWeaponConfigIndex, 0),
            max(ownedWeapon.configs.count - 1, 0)
        )
        _weaponConfigIndex = State(initialValue: safeWeaponConfig)
        _currentWarframeID = State(initialValue: initialWarframe?.id)
        let safeWarframeConfig = min(
            max(initialWarframeConfigIndex, 0),
            max((initialWarframe?.configs.count ?? 1) - 1, 0)
        )
        _currentWarframeConfigIndex = State(initialValue: safeWarframeConfig)
    }

    private var selectedWeaponConfig: InventoryData.OwnedWeapon.Config? {
        guard ownedWeapon.configs.indices.contains(weaponConfigIndex) else { return nil }
        return ownedWeapon.configs[weaponConfigIndex]
    }

    private var selectedWarframe: InventoryData.OwnedWarframe? {
        guard let currentWarframeID else { return nil }
        return availableWarframes.first { $0.id == currentWarframeID }
    }

    private var selectedWarframeConfig: InventoryData.OwnedWarframe.Config? {
        guard let selectedWarframe,
              selectedWarframe.configs.indices.contains(currentWarframeConfigIndex) else {
            return nil
        }
        return selectedWarframe.configs[currentWarframeConfigIndex]
    }

    private var calculatorIsAvailable: Bool {
        calculatorAvailable
    }

    var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: WFUI.s4) {
                    heading
                    weaponBuildCard
                    warframeBuildCard
                    calculationCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle(ownedWeapon.z)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WFTheme.bgSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $openCalculator) {
            DamageCalcView(
                ownedWeapon: ownedWeapon,
                ownedWeaponConfigIndex: weaponConfigIndex,
                ownedWarframe: selectedWarframe,
                warframeConfigIndex: currentWarframeConfigIndex,
                availableWarframes: availableWarframes,
                title: ownedWeapon.z
            )
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("武器配置")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(WFTheme.textPrimary)
            Text("先核对这把武器和当前战甲的 A/B/C 配置；伤害计算会原样带入。")
                .font(.wfBody)
                .foregroundColor(WFTheme.textMuted)
        }
    }

    private var weaponBuildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("武器", trailing: ownedWeapon.categoryLabel)
            HStack(alignment: .top, spacing: WFUI.s3) {
                Image(systemName: "scope")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(WFTheme.cyan)
                    .frame(width: 38, height: 38)
                    .background(WFTheme.cyan.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ownedWeapon.z)
                        .font(.wfTitle)
                        .foregroundColor(WFTheme.textPrimary)
                    Text(ownedWeapon.calcName ?? "该武器尚未接入本机伤害数据")
                        .font(.wfLabel)
                        .foregroundColor(ownedWeapon.calcName == nil ? WFTheme.gold : WFTheme.textMuted)
                }
                Spacer(minLength: 0)
            }

            configPicker(
                configs: ownedWeapon.configs.map(\.label),
                selection: $weaponConfigIndex,
                emptyText: "快照中没有这把武器的 A/B/C 配置。"
            )

            if let config = selectedWeaponConfig {
                weaponBuildDetail(config)
            }
        }
        .wfCardStyle()
    }

    private func weaponBuildDetail(_ config: InventoryData.OwnedWeapon.Config) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            if !config.isExactImport {
                Label("有槽位未能原样导入；以下是来源记录的具体原因。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
                ForEach(config.issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
            }

            let mods = config.normalizedSlots.enumerated().compactMap { index, name -> (Int, String)? in
                guard let name else { return nil }
                return (index, name)
            }
            if mods.isEmpty, config.riven == nil {
                Text("这个配置没有已导入的 Mod。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                Text("已导入的 Mod")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 7)], spacing: 7) {
                    ForEach(Array(mods.enumerated()), id: \.offset) { _, pair in
                        buildPill(slotLabel(pair.0), pair.1)
                    }
                    if let riven = config.riven {
                        buildPill("紫卡", riven.name)
                    }
                }
            }
        }
    }

    private var warframeBuildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("当前战甲", trailing: "自身技能与执政官石")
            Text("这里的战甲只决定你自己持有的技能和石头。另一名战甲给你的 Buff 在下一页以独立施法者加入。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)

            Menu {
                Button("不带当前战甲") {
                    currentWarframeID = nil
                    currentWarframeConfigIndex = 0
                }
                ForEach(availableWarframes) { frame in
                    Button(frame.z) {
                        currentWarframeID = frame.id
                        currentWarframeConfigIndex = 0
                    }
                }
            } label: {
                selectionLabel(
                    icon: "person.crop.square",
                    title: selectedWarframe?.z ?? "不带当前战甲",
                    subtitle: selectedWarframe == nil
                        ? "不会带入自身技能、技能强度或执政官石"
                        : "使用其已导入的 A/B/C 配置"
                )
            }
            .buttonStyle(.plain)

            if let frame = selectedWarframe {
                configPicker(
                    configs: frame.configs.map(\.label),
                    selection: $currentWarframeConfigIndex,
                    emptyText: "快照中没有这套战甲配置。"
                )
                if let config = selectedWarframeConfig {
                    warframeBuildDetail(frame, config)
                }
            }
        }
        .wfCardStyle()
    }

    private func warframeBuildDetail(_ frame: InventoryData.OwnedWarframe,
                                     _ config: InventoryData.OwnedWarframe.Config) -> some View {
        let strength = WarframeStrengthResolver.resolve(frame, configIndex: currentWarframeConfigIndex)
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("通用技能强度")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                Spacer()
                Text(String(format: "%.0f%%", strength.multiplier * 100))
                    .font(.wfNumSmall)
                    .foregroundColor(WFTheme.gold)
            }
            Text("由该战甲的已导入 Mod 和执政官石结算，不可手填；仅作用于第 4 技能的加成会在选择具体技能时加入。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)

            if !config.isExactImport {
                ForEach(config.issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.gold)
                }
            }

            let upgrades = config.upgrades.sorted { $0.slot < $1.slot }
            if !upgrades.isEmpty {
                Text("已导入的战甲 Mod / 赋能")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 7)], spacing: 7) {
                    ForEach(upgrades) { upgrade in
                        buildPill(upgrade.kind, "\(upgrade.name) · \(upgrade.rankLabel)")
                    }
                }
            }

            if !frame.shards.isEmpty {
                Text("执政官石：\(frame.shards.map(\.name).joined(separator: " · "))")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
    }

    private var calculationCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("伤害计算")
            Text(calculatorIsAvailable
                 ? "会带入武器配置 \(selectedWeaponConfig?.label ?? "—")，以及当前战甲配置。外部施法者 Buff 在计算器中独立添加。"
                 : "这把武器的背包配置已经保留，但本机伤害数据尚未包含它，暂时不能打开计算。")
                .font(.wfBody)
                .foregroundColor(calculatorIsAvailable ? WFTheme.textSecondary : WFTheme.gold)
            Button {
                openCalculator = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "function")
                    Text("按此配置计算伤害")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.wfBody)
                .foregroundColor(Color(hex: "1A1408"))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(WFTheme.gold)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!calculatorIsAvailable)
            .opacity(calculatorIsAvailable ? 1 : 0.45)
        }
        .wfCardStyle()
    }

    private func configPicker(configs: [String], selection: Binding<Int>, emptyText: String) -> some View {
        Group {
            if configs.isEmpty {
                Text(emptyText)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            } else {
                HStack(spacing: 7) {
                    ForEach(Array(configs.enumerated()), id: \.offset) { index, label in
                        Button {
                            selection.wrappedValue = index
                        } label: {
                            Text(label)
                                .font(.wfBody)
                                .foregroundColor(index == selection.wrappedValue
                                                 ? Color(hex: "1A1408") : WFTheme.textSecondary)
                                .frame(minWidth: 34)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(index == selection.wrappedValue
                                                            ? WFTheme.gold : WFUI.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func selectionLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: WFUI.s2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(WFTheme.gold)
                .frame(width: 30, height: 30)
                .background(WFTheme.gold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textPrimary)
                Text(subtitle)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(WFTheme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func buildPill(_ label: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(WFTheme.textMuted)
            Text(name)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func slotLabel(_ slot: Int) -> String {
        switch slot {
        case 8: return "Exilus"
        case 9: return "架势"
        case 10: return "赋能"
        default: return "槽位 \(slot + 1)"
        }
    }
}

/// Configuration inspection for the Warframe card in a whole Arsenal preset.
/// It intentionally does not offer a global manual Ability Strength field:
/// the calculator receives its strength from this selected build instead.
struct ArsenalWarframeConfigurationView: View {
    let warframe: InventoryData.OwnedWarframe
    @State private var configIndex: Int

    init(warframe: InventoryData.OwnedWarframe, initialConfigIndex: Int = 0) {
        self.warframe = warframe
        let safeIndex = min(max(initialConfigIndex, 0), max(warframe.configs.count - 1, 0))
        _configIndex = State(initialValue: safeIndex)
    }

    private var selectedConfig: InventoryData.OwnedWarframe.Config? {
        guard warframe.configs.indices.contains(configIndex) else { return nil }
        return warframe.configs[configIndex]
    }

    var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: WFUI.s4) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("战甲配置")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(WFTheme.textPrimary)
                        Text("\(warframe.z) 的配置决定自身技能和作为外部施法者时的 Buff 数值。")
                            .font(.wfBody)
                            .foregroundColor(WFTheme.textMuted)
                    }
                    buildCard
                    abilityCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle(warframe.z)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WFTheme.bgSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var buildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("已导入配置")
            if warframe.configs.isEmpty {
                Text("这份快照没有此战甲的 A/B/C 配置。")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.gold)
            } else {
                HStack(spacing: 7) {
                    ForEach(Array(warframe.configs.enumerated()), id: \.offset) { index, config in
                        Button {
                            configIndex = index
                        } label: {
                            Text(config.label)
                                .font(.wfBody)
                                .foregroundColor(index == configIndex ? Color(hex: "1A1408") : WFTheme.textSecondary)
                                .frame(minWidth: 34)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(index == configIndex ? WFTheme.gold : WFUI.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let config = selectedConfig {
                    let strength = WarframeStrengthResolver.resolve(warframe, configIndex: configIndex)
                    HStack {
                        Text("通用技能强度")
                            .font(.wfBody)
                            .foregroundColor(WFTheme.textSecondary)
                        Spacer()
                        Text(String(format: "%.0f%%", strength.multiplier * 100))
                            .font(.wfNumSmall)
                            .foregroundColor(WFTheme.gold)
                    }
                    Text("由实际装备的 Mod 和执政官石得出；第 4 技能专属加成会在选择具体技能时加入。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    if !config.isExactImport {
                        ForEach(config.issues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.gold)
                        }
                    }
                    ForEach(config.upgrades.sorted { $0.slot < $1.slot }) { upgrade in
                        HStack(alignment: .firstTextBaseline) {
                            Text(upgrade.name)
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textPrimary)
                            Spacer()
                            Text("\(upgrade.kind) · \(upgrade.rankLabel)")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                }
            }
            if !warframe.shards.isEmpty {
                WFHairline()
                Text("执政官石")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                ForEach(warframe.shards) { shard in
                    Text("槽位 \(shard.slot + 1) · \(shard.name)\(shard.isTauforged ? "（Tau）" : "")")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
            }
        }
        .wfCardStyle()
    }

    private var abilityCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("技能")
            Text("实际能用于武器伤害的自身技能或外部 Buff，会在武器的伤害计算页按该配置结算。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            ForEach(warframe.abilities) { ability in
                HStack {
                    Text("\(ability.ordinal)")
                        .font(.wfNumSmall)
                        .foregroundColor(WFTheme.gold)
                        .frame(width: 22, alignment: .leading)
                    Text(ability.name)
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textPrimary)
                    Spacer()
                }
            }
            if let helminth = selectedConfig?.helminth {
                WFHairline()
                Text("Helminth：第 \((helminth.replacedIndex ?? 0) + 1) 槽已替换为 \(helminth.name)")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            }
        }
        .wfCardStyle()
    }
}
