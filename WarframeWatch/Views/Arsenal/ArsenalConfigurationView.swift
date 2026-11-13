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
    let availableCompanions: [InventoryData.OwnedEquipment]
    /// The Arsenal list verifies this against the bundled calculator catalogue.
    /// Keeping it separate from `calcName != nil` avoids offering a button for
    /// an instance whose static definition is not actually in this app build.
    private let calculatorAvailable: Bool

    @ObservedObject private var catalog = WeaponCatalog.shared
    @State private var weaponConfigIndex: Int
    @State private var currentWarframeID: String?
    @State private var currentWarframeConfigIndex: Int
    @State private var openCalculator = false
    @State private var showExtraDetails = false
    @State private var inspectedModCard: ModCardPresentation?

    init(ownedWeapon: InventoryData.OwnedWeapon,
         availableWarframes: [InventoryData.OwnedWarframe],
         availableCompanions: [InventoryData.OwnedEquipment] = [],
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
        self.availableCompanions = availableCompanions.sorted {
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
                    weaponBuildCard
                    warframeBuildCard
                    calculationButton
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
        .task {
            catalog.load()
        }
        .navigationDestination(isPresented: $openCalculator) {
            DamageCalcView(
                ownedWeapon: ownedWeapon,
                ownedWeaponConfigIndex: weaponConfigIndex,
                ownedWarframe: selectedWarframe,
                warframeConfigIndex: currentWarframeConfigIndex,
                availableWarframes: availableWarframes,
                availableCompanions: availableCompanions,
                title: ownedWeapon.z
            )
        }
        .sheet(item: $inspectedModCard) { card in
            VerticalModCardModal(card: card)
        }
    }

    private var weaponCatalogEntry: WeaponEntry? {
        if let calcName = ownedWeapon.calcName,
           let exact = catalog.weapons.first(where: { $0.n.caseInsensitiveCompare(calcName) == .orderedSame }) {
            return exact
        }
        return Self.matchCatalogEntry(
            in: catalog.weapons,
            names: [ownedWeapon.z] + (ownedWeapon.calcName.map { [$0] } ?? [])
        )
    }

    private static func matchCatalogEntry(in weapons: [WeaponEntry], names: [String]) -> WeaponEntry? {
        for raw in names {
            let clean = ArsenalItemThumb.stripAnnotation(raw)
            guard !clean.isEmpty else { continue }
            if let exact = weapons.first(where: {
                $0.n.caseInsensitiveCompare(clean) == .orderedSame
                    || $0.z.caseInsensitiveCompare(clean) == .orderedSame
            }) {
                return exact
            }
            let targetKey = normalizedWeaponLookupKey(clean)
            guard !targetKey.isEmpty else { continue }
            let candidates = weapons.filter { entry in
                normalizedWeaponLookupKey(entry.n) == targetKey
                    || normalizedWeaponLookupKey(entry.z) == targetKey
            }
            if !candidates.isEmpty {
                let preferredSuffixes = ["(大气)", "(atmo-mode)", "(突击步枪)", "(rifle)", "(archwing)"]
                if let preferred = candidates.first(where: { entry in
                    let zn = entry.z.lowercased()
                    let nn = entry.n.lowercased()
                    return preferredSuffixes.contains { zn.contains($0) || nn.contains($0) }
                }) {
                    return preferred
                }
                return candidates.first
            }
        }
        return nil
    }

    private static func normalizedWeaponLookupKey(_ raw: String) -> String {
        var text = ArsenalItemThumb.stripAnnotation(raw)
        if text.uppercased().hasPrefix("<ARCHWING>") {
            text = String(text.dropFirst("<ARCHWING>".count))
        }
        for open in [" (", "（"] {
            if let range = text.range(of: open) {
                text = String(text[..<range.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var weaponMetaLine: String {
        var parts = [ownedWeapon.categoryLabel]
        if let (element, ratio) = ownedWeapon.progenitorElements
            .sorted(by: { $0.key < $1.key })
            .first,
           ratio > 0 {
            let pct = Int((ratio * 100).rounded())
            parts.append("+\(pct)% \(elementLabel(element))")
        }
        if !ownedWeapon.incarnonChoices.isEmpty {
            parts.append("灵化")
        }
        return parts.joined(separator: " · ")
    }

    private var weaponBuildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            HStack(alignment: .center, spacing: WFUI.s3) {
                ArsenalItemThumb(
                    weaponEntry: weaponCatalogEntry,
                    displayName: ownedWeapon.z,
                    fallbackSymbol: "scope",
                    fallbackColor: WFTheme.cyan,
                    size: 58
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownedWeapon.z)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    Text(weaponMetaLine)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            configPicker(
                configs: ownedWeapon.configs.map(\.label),
                selection: $weaponConfigIndex,
                emptyText: "无 A/B/C 配卡记录"
            )

            if let config = selectedWeaponConfig {
                weaponBuildDetail(config)
            }
        }
        .wfCardStyle()
    }

    private func weaponBuildDetail(_ config: InventoryData.OwnedWeapon.Config) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            let mods = config.normalizedSlots.enumerated().compactMap { index, name -> (Int, String)? in
                guard let name else { return nil }
                return (index, name)
            }
            if mods.isEmpty, config.riven == nil {
                Text("当前配置没有已装 Mod")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(mods.enumerated()), id: \.offset) { _, pair in
                        let specialTag: String? = pair.0 == 8 ? "特殊功能" : (pair.0 == 9 ? "架势" : (pair.0 == 10 ? "赋能" : nil))
                        let meta = config.metadata(at: pair.0)
                        let card = ModCardPresentation.make(
                            rawName: pair.1,
                            slotTag: specialTag,
                            rank: meta?.rank,
                            maxRank: meta?.maxRank,
                            id: "weapon-\(pair.0)-\(pair.1)"
                        )
                        Button {
                            inspectedModCard = card
                        } label: {
                            HorizontalModCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                    if let riven = config.riven {
                        let card = ModCardPresentation.make(
                            rawName: riven.name,
                            slotTag: "紫卡",
                            rank: 8,
                            maxRank: 8,
                            isRiven: true,
                            rivenLines: Self.rivenStatLines(riven),
                            id: "weapon-riven-\(riven.name)"
                        )
                        Button {
                            inspectedModCard = card
                        } label: {
                            HorizontalModCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let extraCount = config.unresolvedUpgrades.count + config.nonDamageUpgrades.count + config.issues.count
            if extraCount > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showExtraDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: config.isExactImport ? "info.circle" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(config.isExactImport ? WFTheme.textMuted : WFTheme.gold)
                        Text(config.isExactImport
                             ? "含 \(config.nonDamageUpgrades.count) 张非伤害类 Mod"
                             : "有 \(config.unresolvedUpgrades.count + config.issues.count) 项未参与计算")
                            .font(.wfLabel)
                            .foregroundColor(config.isExactImport ? WFTheme.textMuted : WFTheme.gold)
                        Spacer()
                        Image(systemName: showExtraDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(WFTheme.textMuted)
                    }
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)

                if showExtraDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(config.unresolvedUpgrades) { upgrade in
                            let rank = upgrade.rankLabel.map { "（\($0)）" } ?? ""
                            let name = NativeDamageCatalog.shared.localizedUpgradeName(upgrade.name)
                            Text("未计算：\(name)\(rank) · \(upgrade.reason)")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.gold)
                        }
                        ForEach(config.issues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.gold)
                        }
                        ForEach(config.nonDamageUpgrades) { upgrade in
                            let name = NativeDamageCatalog.shared.localizedUpgradeName(upgrade.name)
                            Text("非伤害卡：\(name)")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var warframeBuildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            HStack {
                Text("携带战甲")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                Spacer()
                if let frame = selectedWarframe {
                    let strength = WarframeStrengthResolver.resolve(frame, configIndex: currentWarframeConfigIndex)
                    Text(String(format: "技能强度 %.0f%%", strength.multiplier * 100))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(WFTheme.gold)
                }
            }

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
                HStack(spacing: WFUI.s3) {
                    ArsenalItemThumb(
                        weaponEntry: nil,
                        displayName: selectedWarframe?.z,
                        fallbackSymbol: "person.crop.square",
                        fallbackColor: WFTheme.gold,
                        size: 38
                    )
                    Text(selectedWarframe?.z ?? "不带当前战甲")
                        .font(.wfBody)
                        .foregroundColor(selectedWarframe == nil ? WFTheme.textMuted : WFTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(WFTheme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(WFUI.raised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if let frame = selectedWarframe {
                configPicker(
                    configs: frame.configs.map(\.label),
                    selection: $currentWarframeConfigIndex,
                    emptyText: "无战甲 A/B/C 配置"
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
        let upgrades = config.upgrades.sorted { $0.slot < $1.slot }
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            if !upgrades.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(upgrades) { upgrade in
                        let slotTag = upgrade.kind.lowercased() == "mod" ? nil : localizedKindLabel(upgrade.kind)
                        let card = ModCardPresentation.make(
                            rawName: upgrade.name,
                            slotTag: slotTag,
                            rank: upgrade.rank,
                            maxRank: upgrade.maxRank,
                            id: "wf-select-\(upgrade.slot)-\(upgrade.name)"
                        )
                        Button {
                            inspectedModCard = card
                        } label: {
                            HorizontalModCardView(card: card)
                        }
                        .buttonStyle(.plain)
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

    private var calculationButton: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Button {
                openCalculator = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "function")
                    Text("计算此配装伤害")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "1A1408"))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(WFTheme.gold)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!calculatorIsAvailable)
            .opacity(calculatorIsAvailable ? 1 : 0.45)

            if !calculatorIsAvailable {
                Text("该武器暂未收录进本地伤害数据库。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func configPicker(configs: [String], selection: Binding<Int>, emptyText: String) -> some View {
        Group {
            if configs.isEmpty {
                Text(emptyText)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            } else {
                ConfigSelectorPillBar(labels: configs, selection: selection)
            }
        }
    }

    private func buildPill(_ name: String, detail: String? = nil, accent: Color = WFTheme.textSecondary) -> some View {
        ArsenalUpgradePill(rawName: name, detail: detail, accent: accent)
    }

    private func localizedKindLabel(_ kind: String) -> String {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "arcane", "weapon_mist": return "赋能"
        case "aura": return "光环"
        case "exilus": return "特殊功能"
        case "stance": return "架势"
        case "mod": return "振幅晶体"
        default: return kind
        }
    }

    private func compactRank(_ metadata: InventoryData.OwnedWeapon.Config.SlotMetadata) -> String? {
        switch (metadata.rank, metadata.maxRank) {
        case let (.some(rank), .some(maximum)): return "\(rank)/\(maximum)"
        case let (.some(rank), .none): return "Lv.\(rank)"
        default: return nil
        }
    }

    private func compactUpgradeRank(_ upgrade: InventoryData.OwnedWarframe.Upgrade) -> String {
        switch (upgrade.rank, upgrade.maxRank) {
        case let (.some(rank), .some(maximum)): return "\(rank)/\(maximum)"
        case let (.some(rank), .none): return "Lv.\(rank)"
        default: return "未确认"
        }
    }

    private func elementLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "toxin": return "毒素"
        case "heat": return "火焰"
        case "cold": return "冰冻"
        case "electricity": return "电击"
        case "impact": return "冲击"
        case "radiation": return "辐射"
        case "magnetic": return "磁力"
        default: return raw
        }
    }

    private func slotLabel(_ slot: Int) -> String {
        switch slot {
        case 8: return "Exilus"
        case 9: return "架势"
        case 10: return "赋能"
        default: return "槽位 \(slot + 1)"
        }
    }

    private static func rivenStatLines(_ riven: InventoryData.OwnedWeapon.ImportedRiven) -> [String] {
        var lines: [String] = []
        let fmt: (String, Double?) -> Void = { label, value in
            guard let value, abs(value) > 0.0001 else { return }
            lines.append(String(format: "%+.1f%% %@", value * 100, label))
        }
        fmt("伤害", riven.damage)
        fmt("多重射击", riven.multishot)
        fmt("暴击率", riven.critChance)
        fmt("暴击伤害", riven.critDamage)
        fmt("触发几率", riven.statusChance)
        fmt("异常持续时间", riven.statusDuration)
        fmt("射速 / 攻速", riven.fireRate)
        fmt("装填速度", riven.reloadSpeed)
        fmt("弹匣容量", riven.magazineSize)
        fmt("弹药效率", riven.ammoEfficiency)
        fmt("重击效率", riven.meleeComboEfficiency)
        fmt("派系伤害", riven.faction)
        for (faction, val) in (riven.factionBonuses ?? [:]).sorted(by: { $0.key < $1.key }) where abs(val) > 0.0001 {
            lines.append(String(format: "%+.1f%% 对 %@ 伤害", val * 100, faction))
        }
        let elemNames = ["heat": "火焰", "cold": "冰冻", "electricity": "电击", "toxin": "毒素"]
        for (elem, val) in (riven.elements ?? [:]).sorted(by: { $0.key < $1.key }) where abs(val) > 0.0001 {
            lines.append(String(format: "%+.1f%% %@", val * 100, elemNames[elem.lowercased()] ?? elem))
        }
        let physNames = ["impact": "冲击", "puncture": "穿刺", "slash": "切割"]
        for (phys, val) in (riven.physical ?? [:]).sorted(by: { $0.key < $1.key }) where abs(val) > 0.0001 {
            lines.append(String(format: "%+.1f%% %@", val * 100, physNames[phys.lowercased()] ?? phys))
        }
        for effect in riven.displayOnly ?? [] {
            lines.append(String(format: "%+.1f%% %@", effect.value * 100, effect.label))
        }
        for effect in riven.unresolved ?? [] {
            lines.append(effect.label)
        }
        return lines
    }
}

/// Configuration inspection for a companion or Archwing body.  Its Mod/Arcane
/// layout is imported from the same account snapshot as weapons, but the body
/// is not incorrectly offered to the normal weapon damage calculator.
struct ArsenalEquipmentConfigurationView: View {
    let equipment: InventoryData.OwnedEquipment
    @State private var configIndex: Int
    @State private var inspectedModCard: ModCardPresentation?

    init(equipment: InventoryData.OwnedEquipment, initialConfigIndex: Int = 0) {
        self.equipment = equipment
        let safeIndex = min(max(initialConfigIndex, 0), max(equipment.configs.count - 1, 0))
        _configIndex = State(initialValue: safeIndex)
    }

    private var selectedConfig: InventoryData.OwnedEquipment.Config? {
        equipment.config(at: configIndex)
    }

    var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: WFUI.s4) {
                    buildCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle(equipment.z)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WFTheme.bgSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $inspectedModCard) { card in
            VerticalModCardModal(card: card)
        }
    }

    private var buildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            HStack(alignment: .center, spacing: WFUI.s3) {
                ArsenalItemThumb(
                    weaponEntry: nil,
                    displayName: equipment.z,
                    fallbackSymbol: equipment.inventoryCategory == "SpaceSuits" ? "airplane" : "pawprint",
                    fallbackColor: WFTheme.cyan,
                    size: 54
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(equipment.z)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    Text(equipment.categoryLabel)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if equipment.configs.isEmpty {
                Text("暂无 A/B/C 配卡记录")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.gold)
            } else {
                ConfigSelectorPillBar(labels: equipment.configs.map(\.label), selection: $configIndex)
                if let config = selectedConfig {
                    if !config.isExactImport {
                        Label(config.issues.first ?? "部分槽位等级未能完全确认",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }

                    let upgrades = config.upgrades.sorted { $0.slot < $1.slot }
                    if upgrades.isEmpty {
                        Text("当前配置没有已装 Mod")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(upgrades) { upgrade in
                                let slotTag = upgrade.kind.lowercased() == "mod" ? nil : localizedKindLabel(upgrade.kind)
                                let card = ModCardPresentation.make(
                                    rawName: upgrade.name,
                                    slotTag: slotTag,
                                    rank: upgrade.rank,
                                    maxRank: upgrade.maxRank,
                                    id: "equip-\(upgrade.slot)-\(upgrade.name)"
                                )
                                Button {
                                    inspectedModCard = card
                                } label: {
                                    HorizontalModCardView(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .wfCardStyle()
    }

    private func upgradePill(_ upgrade: InventoryData.OwnedEquipment.Upgrade) -> some View {
        let rankText: String = {
            switch (upgrade.rank, upgrade.maxRank) {
            case let (.some(r), .some(m)): return "\(r)/\(m)"
            case let (.some(r), .none): return "Lv.\(r)"
            default: return "未确认"
            }
        }()
        return ArsenalUpgradePill(
            rawName: upgrade.name,
            detail: "\(localizedKindLabel(upgrade.kind)) · \(rankText)",
            accent: WFTheme.gold
        )
    }

    private func localizedKindLabel(_ kind: String) -> String {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "arcane", "weapon_mist": return "赋能"
        case "aura": return "光环"
        case "exilus": return "特殊功能"
        case "stance": return "架势"
        case "mod": return "振幅晶体"
        default: return kind
        }
    }
}

/// Configuration inspection for the Warframe card in a whole Arsenal preset.
/// It intentionally does not offer a global manual Ability Strength field:
/// the calculator receives its strength from this selected build instead.
struct ArsenalWarframeConfigurationView: View {
    let warframe: InventoryData.OwnedWarframe
    @State private var configIndex: Int
    @State private var inspectedModCard: ModCardPresentation?

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
        .sheet(item: $inspectedModCard) { card in
            VerticalModCardModal(card: card)
        }
    }

    private var buildCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            let strength = WarframeStrengthResolver.resolve(warframe, configIndex: configIndex)
            HStack(alignment: .center, spacing: WFUI.s3) {
                ArsenalItemThumb(
                    weaponEntry: nil,
                    displayName: warframe.z,
                    fallbackSymbol: "person.crop.square",
                    fallbackColor: WFTheme.gold,
                    size: 54
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(warframe.z)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    Text(String(format: "技能强度 %.0f%%", strength.multiplier * 100))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(WFTheme.gold)
                }
                Spacer(minLength: 0)
            }

            if warframe.configs.isEmpty {
                Text("暂无 A/B/C 配卡记录")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.gold)
            } else {
                ConfigSelectorPillBar(labels: warframe.configs.map(\.label), selection: $configIndex)
                if let config = selectedConfig {
                    if !config.isExactImport {
                        Label(config.issues.first ?? "部分槽位等级未能完全确认",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }
                    let upgrades = config.upgrades.sorted { $0.slot < $1.slot }
                    if !upgrades.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(upgrades) { upgrade in
                                let slotTag = upgrade.kind.lowercased() == "mod" ? nil : localizedKindLabel(upgrade.kind)
                                let card = ModCardPresentation.make(
                                    rawName: upgrade.name,
                                    slotTag: slotTag,
                                    rank: upgrade.rank,
                                    maxRank: upgrade.maxRank,
                                    id: "wf-\(upgrade.slot)-\(upgrade.name)"
                                )
                                Button {
                                    inspectedModCard = card
                                } label: {
                                    HorizontalModCardView(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if !warframe.shards.isEmpty {
                WFHairline()
                Text("执政官石：\(warframe.shards.map { "\($0.name)\($0.isTauforged ? " (Tau)" : "")" }.joined(separator: " · "))")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
        .wfCardStyle()
    }

    private var abilityCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("技能")
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
                Text("Helminth：第 \((helminth.replacedIndex ?? 0) + 1) 槽 → \(helminth.name)")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.gold)
            }
        }
        .wfCardStyle()
    }

    private func localizedKindLabel(_ kind: String) -> String {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "arcane", "weapon_mist": return "赋能"
        case "aura": return "光环"
        case "exilus": return "特殊功能"
        case "stance": return "架势"
        case "mod": return "振幅晶体"
        default: return kind
        }
    }
}

/// 统一展示配卡 Mod / 赋能 / 紫卡的缩略图与中文名称。
private struct ArsenalUpgradePill: View {
    let rawName: String
    let detail: String?
    let accent: Color

    @ObservedObject private var damageCatalog = NativeDamageCatalog.shared

    private var localizedName: String {
        damageCatalog.localizedUpgradeName(rawName)
    }

    private var isRiven: Bool {
        detail?.contains("紫卡") == true
    }

    var body: some View {
        HStack(spacing: 8) {
            UpgradeIconThumb(
                rawName: isRiven ? "Riven" : rawName,
                fallbackSymbol: isRiven ? "sparkles" : "square.stack.3d.up.fill",
                accent: accent,
                size: 30
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedName)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(accent)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(WFUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UpgradeIconThumb: View {
    let rawName: String
    let fallbackSymbol: String
    let accent: Color
    let size: CGFloat

    @ObservedObject private var damageCatalog = NativeDamageCatalog.shared
    @State private var image: UIImage?
    @State private var remoteURL: URL?
    @State private var loadedKey = ""

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case let .success(loaded):
                        loaded.resizable().scaledToFit().padding(1)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(WFTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: rawName) {
            if loadedKey != rawName {
                image = nil
                remoteURL = nil
                loadedKey = rawName
            }
            let urls: (local: URL?, remote: URL?)
            if rawName == "Riven" {
                urls = (damageCatalog.localModIcon(named: "riven.webp"), nil)
            } else {
                urls = damageCatalog.modIconURLs(forName: rawName)
            }
            remoteURL = urls.remote
            if let local = urls.local {
                let px = size * UIScreen.main.scale
                let loaded = await WeaponIconStore.shared.load(
                    url: local,
                    cacheKey: local.path,
                    maxPixel: px
                )
                if !Task.isCancelled {
                    image = loaded
                }
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: fallbackSymbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundColor(accent.opacity(0.75))
    }
}

private struct ConfigSelectorPillBar: View {
    let labels: [String]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    let isSelected = index == selection
                    Button {
                        selection = index
                    } label: {
                        Text(label)
                            .font(.wfBody)
                            .lineLimit(1)
                            .foregroundColor(isSelected ? Color(hex: "1A1408") : WFTheme.textSecondary)
                            .frame(minWidth: 34)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(isSelected ? WFTheme.gold : WFUI.raised))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .contentShape(Rectangle())
        .zIndex(10)
    }
}
