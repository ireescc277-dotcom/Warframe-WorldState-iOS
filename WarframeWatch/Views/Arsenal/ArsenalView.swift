import SwiftUI
import UIKit
import ImageIO

/// 军械库：先展示一套账号快照中的整体配置，再允许进入具体装备的 A/B/C 页面。
///
/// 公共武器数据库只提供图标、中文名和空计算器的手动选择器；它不是这个页面的
/// 列表来源。这样同名武器的不同实例、继承元素和配置不会被合并丢掉。
public struct ArsenalView: View {
    @ObservedObject private var catalog = WeaponCatalog.shared
    @ObservedObject private var inventory = InventoryFeed.shared

    private enum Page: String, CaseIterable, Identifiable {
        case loadout
        case inventory

        var id: String { rawValue }
        var label: String {
            switch self {
            case .loadout: return "配置"
            case .inventory: return "装备列表"
            }
        }
    }

    @State private var page: Page = ArsenalView.seededPage
    @State private var category: WeaponCategory = ArsenalView.seededCategory
    @State private var query = ""
    @State private var pushedOwned: InventoryData.OwnedWeapon?
    @State private var pushedGeneric: WeaponEntry?
    @State private var pushedWarframe: InventoryData.OwnedWarframe?
    @State private var pushedEquipment: InventoryData.OwnedEquipment?
    @State private var pushedWeaponConfigIndex = 0
    @State private var pushedWarframeConfigIndex = 0
    @State private var pushedEquipmentConfigIndex = 0
    @State private var selectedLoadoutID: String?
    @State private var selectedCompanionLoadoutID: String?
    @State private var selectedArchwingLoadoutID: String?
    @State private var showConfiguration = false
    @State private var showWarframeConfiguration = false
    @State private var showEquipmentConfiguration = false
    @State private var showCalc = false
    @State private var showGearWheel = false
    @State private var openCalc = ArsenalView.seededCalc

    public init() {}

    /// `simctl` 点不了屏幕，靠启动参数把分类和计算器直接摆出来给 CI 拍。
    private static var seededCategory: WeaponCategory {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-arsenalCat"), args.index(after: i) < args.endIndex
        else { return .all }
        return WeaponCategory(rawValue: args[args.index(after: i)]) ?? .all
    }

    private static var seededCalc: Bool {
        CommandLine.arguments.contains("-openCalc")
    }

    /// Visual CI explicitly asks for a weapon category.  In that case it
    /// needs the inventory list; ordinary launches start at the whole loadout
    /// configuration just like the in-game Arsenal.
    private static var seededPage: Page {
        CommandLine.arguments.contains("-arsenalCat") ? .inventory : .loadout
    }

    /// `-arsenalConfigWeapon Torid`：CI 直接打开这把背包武器的配置页。
    /// `simctl` 点不了屏，因此这只用于截图门禁，不改变正常导航。
    private static var seededConfigurationWeapon: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-arsenalConfigWeapon"), args.index(after: i) < args.endIndex
        else { return nil }
        return args[args.index(after: i)]
    }

    /// `-arsenalConfigEquipment 名称`：视觉 CI 直接打开同伴/Archwing
    /// 本体的配置页。和武器 hook 一样，只绕过 simctl 无法点按的问题。
    private static var seededConfigurationEquipment: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-arsenalConfigEquipment"), args.index(after: i) < args.endIndex
        else { return nil }
        return args[args.index(after: i)]
    }

    /// `-calcWeapon Torid`：CI 要一张原生计算器结果图，无法点配置页按钮时直接进入。
    private static var seededWeapon: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-calcWeapon"), args.index(after: i) < args.endIndex
        else { return nil }
        return args[args.index(after: i)]
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        header
                        pagePicker
                        if page == .loadout {
                            loadoutContent
                        } else {
                            searchBox
                            categoryBar
                            list
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await inventory.refresh()
                    selectDefaultLoadoutIfNeeded()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                catalog.load()
                // Warm the JSON/DataStore once while the user is looking at
                // their owned list.  We do not compute every config eagerly:
                // target/environment options would make such cached answers
                // stale.  The selected config is still prefilled and its real
                // calculation remains off the main thread.
                _ = NativeDamageCatalog.shared
                selectDefaultLoadoutIfNeeded()
                await inventory.refresh()
                selectDefaultLoadoutIfNeeded()
                if let want = ArsenalView.seededConfigurationWeapon,
                   pushedOwned == nil,
                   let owned = ownedWeapons.first(where: { $0.calcName == want }) {
                    openWeaponConfiguration(owned, from: contextualLoadout(for: owned))
                } else if let want = ArsenalView.seededConfigurationEquipment,
                          pushedEquipment == nil,
                          let equipment = (ownedCompanions + ownedCompanionWeapons + ownedArchwings)
                            .first(where: { $0.z == want }) {
                    openEquipmentConfiguration(equipment, initialConfigIndex: 0)
                } else if let want = ArsenalView.seededWeapon,
                   pushedGeneric == nil,
                   let hit = catalog.weapons.first(where: { $0.n == want }) {
                    pushedGeneric = hit
                    showCalc = true
                }
            }
            // iOS 16 没有 navigationDestination(item:)，用 isPresented + 暂存数据
            .navigationDestination(isPresented: $showConfiguration) {
                if let owned = pushedOwned {
                    ArsenalWeaponConfigurationView(
                        ownedWeapon: owned,
                        availableWarframes: inventory.data?.ownedWarframes ?? [],
                        availableCompanions: inventory.data?.ownedCompanions ?? [],
                        initialWeaponConfigIndex: pushedWeaponConfigIndex,
                        initialWarframe: pushedWarframe,
                        initialWarframeConfigIndex: pushedWarframeConfigIndex,
                        calculatorAvailable: canCalculate(owned)
                    )
                } else {
                    EmptyView()
                }
            }
            .navigationDestination(isPresented: $showWarframeConfiguration) {
                if let frame = pushedWarframe {
                    ArsenalWarframeConfigurationView(
                        warframe: frame,
                        initialConfigIndex: pushedWarframeConfigIndex
                    )
                } else {
                    EmptyView()
                }
            }
            .navigationDestination(isPresented: $showEquipmentConfiguration) {
                if let equipment = pushedEquipment {
                    ArsenalEquipmentConfigurationView(
                        equipment: equipment,
                        initialConfigIndex: pushedEquipmentConfigIndex
                    )
                } else {
                    EmptyView()
                }
            }
            .navigationDestination(isPresented: $showCalc) {
                if let w = pushedGeneric {
                    DamageCalcView(
                        weapon: w.n,
                        availableWarframes: inventory.data?.ownedWarframes ?? [],
                        availableCompanions: inventory.data?.ownedCompanions ?? [],
                        title: w.z
                    )
                } else {
                    DamageCalcView(
                        weapon: nil,
                        availableWarframes: inventory.data?.ownedWarframes ?? [],
                        availableCompanions: inventory.data?.ownedCompanions ?? [],
                        title: "伤害计算"
                    )
                }
            }
            .navigationDestination(isPresented: $openCalc) {
                DamageCalcView(
                    weapon: nil,
                    availableWarframes: inventory.data?.ownedWarframes ?? [],
                    availableCompanions: inventory.data?.ownedCompanions ?? [],
                    title: "伤害计算"
                )
            }
        }
    }

    // MARK: - 头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("军械库")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                Text(arsenalSubtitle)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            Spacer()
            Button {
                openCalc = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "function")
                        .font(.system(size: 12, weight: .semibold))
                    Text("自由计算")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(WFTheme.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(WFTheme.gold.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(WFTheme.gold.opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var pagePicker: some View {
        HStack(spacing: 7) {
            ForEach(Page.allCases) { candidate in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { page = candidate }
                } label: {
                    Text(candidate.label)
                        .font(.system(size: 12, weight: page == candidate ? .semibold : .regular))
                        .foregroundColor(page == candidate ? Color(hex: "1A1408") : WFTheme.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(page == candidate ? WFTheme.gold : WFUI.surface))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var searchBox: some View {
        HStack(spacing: WFUI.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(WFTheme.textMuted)
            TextField("搜武器名（中英文都行）", text: $query)
                .font(.wfBody)
                .foregroundColor(WFTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(WFTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 10)
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WFUI.s2) {
                ForEach(WeaponCategory.allCases) { cat in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { category = cat }
                    } label: {
                        Text(cat.label)
                            .font(.system(size: 12, weight: category == cat ? .semibold : .regular))
                            .foregroundColor(category == cat ? Color(hex: "1A1408") : WFTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(category == cat ? WFTheme.gold : WFUI.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - 列表

    private var ownedWeapons: [InventoryData.OwnedWeapon] {
        inventory.data?.ownedWeapons ?? []
    }

    private var ownedWarframes: [InventoryData.OwnedWarframe] {
        inventory.data?.ownedWarframes ?? []
    }

    private var ownedCompanions: [InventoryData.OwnedEquipment] {
        inventory.data?.ownedCompanions ?? []
    }

    private var ownedCompanionWeapons: [InventoryData.OwnedEquipment] {
        inventory.data?.ownedCompanionWeapons ?? []
    }

    private var ownedArchwings: [InventoryData.OwnedEquipment] {
        inventory.data?.ownedArchwings ?? []
    }

    private var equippedGear: [InventoryData.EquippedGearItem] {
        inventory.data?.equippedGear ?? []
    }

    private var loadouts: [InventoryData.Loadout] {
        inventory.data?.loadouts ?? []
    }

    private var normalLoadouts: [InventoryData.Loadout] {
        loadouts.filter { $0.kind == .normal }
    }

    private var companionLoadouts: [InventoryData.Loadout] {
        loadouts.filter { $0.kind == .companion }
    }

    private var archwingLoadouts: [InventoryData.Loadout] {
        loadouts.filter { $0.kind == .archwing }
    }

    private var selectedLoadout: InventoryData.Loadout? {
        guard let selectedLoadoutID else { return nil }
        return normalLoadouts.first { $0.id == selectedLoadoutID }
    }

    private var selectedCompanionLoadout: InventoryData.Loadout? {
        guard let selectedCompanionLoadoutID else { return nil }
        return companionLoadouts.first { $0.id == selectedCompanionLoadoutID }
    }

    private var selectedArchwingLoadout: InventoryData.Loadout? {
        guard let selectedArchwingLoadoutID else { return nil }
        return archwingLoadouts.first { $0.id == selectedArchwingLoadoutID }
    }

    private var arsenalSubtitle: String {
        guard inventory.data != nil else {
            return inventory.fetching ? "正在同步军械库…" : "暂无军械库数据"
        }
        if page == .inventory {
            return weaponSubtitle
        }
        if let loadout = selectedLoadout {
            return "当前预设：\(loadout.name)"
        }
        return "军械库配置"
    }

    private var weaponSubtitle: String {
        if catalog.failed {
            return "共 \(ownedWeapons.count) 把武器 · 伤害数据不可用"
        }
        return "共 \(ownedWeapons.count) 把武器"
    }

    private func selectDefaultLoadoutIfNeeded() {
        let normal = normalLoadouts
        if normal.isEmpty {
            selectedLoadoutID = nil
        } else if selectedLoadoutID == nil || !normal.contains(where: { $0.id == selectedLoadoutID }) {
            selectedLoadoutID = normal.first(where: { $0.snapshotMarkedActive })?.id ?? normal[0].id
        }

        let companion = companionLoadouts
        if companion.isEmpty {
            selectedCompanionLoadoutID = nil
        } else if selectedCompanionLoadoutID == nil
                    || !companion.contains(where: { $0.id == selectedCompanionLoadoutID }) {
            selectedCompanionLoadoutID = companion.first(where: { $0.snapshotMarkedActive })?.id
                ?? companion[0].id
        }

        let archwing = archwingLoadouts
        if archwing.isEmpty {
            selectedArchwingLoadoutID = nil
        } else if selectedArchwingLoadoutID == nil
                    || !archwing.contains(where: { $0.id == selectedArchwingLoadoutID }) {
            selectedArchwingLoadoutID = archwing.first(where: { $0.snapshotMarkedActive })?.id
                ?? archwing[0].id
        }
    }

    private var loadoutContent: some View {
        Group {
            if inventory.data == nil {
                Text(inventory.failed
                     ? "未能读取军械库数据，下拉刷新或使用右上角「自由计算」。"
                     : "正在读取军械库…")
                    .font(.wfBody)
                    .foregroundColor(inventory.failed ? WFTheme.red : WFTheme.textMuted)
                    .padding(.vertical, WFUI.s4)
            } else {
                VStack(alignment: .leading, spacing: WFUI.s4) {
                    normalLoadoutSection
                    companionLoadoutSection
                    archwingLoadoutSection
                    gearWheelSection
                }
            }
        }
    }

    private var normalLoadoutSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            sectionHeaderWithPicker(
                title: "当前配装",
                choices: normalLoadouts,
                selection: $selectedLoadoutID,
                selectedName: selectedLoadout?.name
            )
            if let loadout = selectedLoadout {
                loadoutCard(loadout)
            } else {
                sourceEmptyCard("暂无战甲配装预设")
            }
        }
    }

    private var companionLoadoutSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            sectionHeaderWithPicker(
                title: "同伴",
                choices: companionLoadouts,
                selection: $selectedCompanionLoadoutID,
                selectedName: selectedCompanionLoadout?.name
            )
            if let loadout = selectedCompanionLoadout {
                loadoutCard(loadout)
            } else if let companion = ownedCompanions.first {
                equipmentFallbackRow(companion, role: .companion)
            } else {
                sourceEmptyCard("暂无同伴预设")
            }
        }
    }

    private var gearWheelSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showGearWheel.toggle()
                }
            } label: {
                HStack(spacing: WFUI.s3) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(WFTheme.gold)
                        .frame(width: 40, height: 40)
                        .background(WFTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("物品轮")
                            .font(.wfTitle)
                            .foregroundColor(WFTheme.textPrimary)
                        Text(equippedGear.isEmpty ? "暂无携带物品" : "已装备 \(equippedGear.count) 项")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                    }
                    Spacer()
                    Image(systemName: showGearWheel ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(WFTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showGearWheel && !equippedGear.isEmpty {
                WFHairline().padding(.vertical, 2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 7)], spacing: 7) {
                    ForEach(equippedGear) { gear in
                        HStack(spacing: 6) {
                            Text(gear.name)
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            if let count = gear.count {
                                Text("×\(count)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(WFTheme.gold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(WFUI.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 10)
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private var archwingLoadoutSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            sectionHeaderWithPicker(
                title: "Archwing",
                choices: archwingLoadouts,
                selection: $selectedArchwingLoadoutID,
                selectedName: selectedArchwingLoadout?.name
            )
            if let loadout = selectedArchwingLoadout {
                loadoutCard(loadout)
            } else if let archwing = ownedArchwings.first {
                equipmentFallbackRow(archwing, role: .archwing)
            } else {
                sourceEmptyCard("暂无 Archwing 预设")
            }
        }
    }

    private func sourceEmptyCard(_ text: String) -> some View {
        Text(text)
            .font(.wfBody)
            .foregroundColor(WFTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WFUI.s3)
            .background(WFUI.surface)
            .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func sectionHeaderWithPicker(title: String,
                                         choices: [InventoryData.Loadout],
                                         selection: Binding<String?>,
                                         selectedName: String?) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            Spacer()
            if choices.count > 1, let selectedName {
                Menu {
                    ForEach(choices) { loadout in
                        Button(loadoutMenuLabel(loadout)) {
                            selection.wrappedValue = loadout.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(WFTheme.gold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(WFTheme.gold.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else if let selectedName {
                Text(selectedName)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, WFUI.s1)
    }

    private func loadoutMenuLabel(_ loadout: InventoryData.Loadout) -> String {
        loadout.isFavorite ? "★ \(loadout.name)" : loadout.name
    }

    private func loadoutCard(_ loadout: InventoryData.Loadout) -> some View {
        let roles = roles(for: loadout.kind)
        return VStack(spacing: 0) {
            ForEach(Array(roles.enumerated()), id: \.element) { index, role in
                loadoutEquipmentRow(role, slot: loadout.slot(role), in: loadout)
                if index < roles.count - 1 {
                    WFHairline().padding(.leading, 68)
                }
            }
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func roles(for kind: InventoryData.Loadout.Kind) -> [InventoryData.Loadout.Slot.Role] {
        switch kind {
        case .normal:
            return [.warframe, .primary, .secondary, .melee, .heavy]
        case .companion:
            return [.companion, .companionWeapon]
        case .archwing:
            return [.archwing, .archgun, .archmelee]
        }
    }

    private func loadoutEquipmentRow(_ role: InventoryData.Loadout.Slot.Role,
                                     slot: InventoryData.Loadout.Slot?,
                                     in loadout: InventoryData.Loadout) -> some View {
        let frame = role == .warframe ? warframe(for: slot) : nil
        let equipment = equipment(for: slot)
        let weapon = role == .warframe || equipment != nil ? nil : weapon(for: slot)
        let name = frame?.z ?? equipment?.z ?? weapon?.z ?? slot?.displayName ?? "未装备"
        let weaponEntry = weapon.flatMap { catalogEntry(for: $0) }
            ?? catalogEntry(named: equipment?.z ?? slot?.displayName)
        let configPill = slot?.configLabel.map { "配置 \($0)" }
        let isAvailable = frame != nil || equipment != nil || weapon != nil

        return Button {
            if let frame {
                pushedWarframe = frame
                pushedWarframeConfigIndex = slot?.configIndex ?? 0
                showWarframeConfiguration = true
            } else if let equipment {
                openEquipmentConfiguration(equipment, initialConfigIndex: slot?.configIndex ?? 0)
            } else if let weapon {
                openWeaponConfiguration(weapon, from: loadout)
            }
        } label: {
            HStack(spacing: WFUI.s3) {
                ArsenalItemThumb(
                    weaponEntry: weaponEntry,
                    displayName: name == "未装备" ? nil : name,
                    fallbackSymbol: symbol(for: role),
                    fallbackColor: color(for: role),
                    size: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.wfTitle)
                        .foregroundColor(isAvailable ? WFTheme.textPrimary : WFTheme.textMuted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(role.label)
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                        if let issue = slot?.sourceIssue {
                            Text("· \(issue)")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.gold)
                                .lineLimit(1)
                        } else if slot?.isHidden == true {
                            Text("· 隐藏")
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                }

                Spacer(minLength: WFUI.s2)

                if let configPill {
                    Text(configPill)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isAvailable ? WFTheme.gold : WFTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(WFUI.raised))
                }

                if isAvailable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(WFTheme.textMuted)
                }
            }
            .padding(.horizontal, WFUI.s3)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.52)
    }

    private func equipmentFallbackRow(_ equipment: InventoryData.OwnedEquipment,
                                      role: InventoryData.Loadout.Slot.Role) -> some View {
        Button {
            openEquipmentConfiguration(equipment, initialConfigIndex: 0)
        } label: {
            HStack(spacing: WFUI.s3) {
                ArsenalItemThumb(
                    weaponEntry: catalogEntry(named: equipment.z),
                    displayName: equipment.z,
                    fallbackSymbol: symbol(for: role),
                    fallbackColor: color(for: role),
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(equipment.z)
                        .font(.wfTitle)
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(role.label) · \(equipment.configs.count) 套配置")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Spacer(minLength: WFUI.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
            }
            .padding(.horizontal, WFUI.s3)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func symbol(for role: InventoryData.Loadout.Slot.Role) -> String {
        switch role {
        case .warframe: return "person.crop.square"
        case .primary: return "scope"
        case .secondary: return "target"
        case .melee: return "sparkles"
        case .heavy: return "bolt.horizontal.circle"
        case .companion: return "pawprint"
        case .companionWeapon: return "scope"
        case .archwing: return "airplane"
        case .archgun: return "scope"
        case .archmelee: return "sparkles"
        }
    }

    private func color(for role: InventoryData.Loadout.Slot.Role) -> Color {
        switch role {
        case .warframe: return WFTheme.gold
        case .primary: return WFTheme.cyan
        case .secondary: return WFTheme.purple
        case .melee: return WFTheme.green
        case .heavy: return WFTheme.red
        case .companion: return WFTheme.cyan
        case .companionWeapon: return WFTheme.green
        case .archwing: return WFTheme.purple
        case .archgun: return WFTheme.cyan
        case .archmelee: return WFTheme.green
        }
    }

    private func warframe(for slot: InventoryData.Loadout.Slot?) -> InventoryData.OwnedWarframe? {
        guard let id = slot?.itemID else { return nil }
        return ownedWarframes.first { $0.id == id }
    }

    private func weapon(for slot: InventoryData.Loadout.Slot?) -> InventoryData.OwnedWeapon? {
        guard let id = slot?.itemID else { return nil }
        return ownedWeapons.first { $0.id == id }
    }

    private func equipment(for slot: InventoryData.Loadout.Slot?) -> InventoryData.OwnedEquipment? {
        guard let slot, let id = slot.itemID else { return nil }
        switch slot.role {
        case .companion:
            return ownedCompanions.first { $0.id == id }
        case .companionWeapon:
            return ownedCompanionWeapons.first { $0.id == id }
        case .archwing:
            return ownedArchwings.first { $0.id == id }
        default:
            return nil
        }
    }

    private func contextualLoadout(for weapon: InventoryData.OwnedWeapon) -> InventoryData.Loadout? {
        if let selectedLoadout,
           selectedLoadout.slots.contains(where: { $0.itemID == weapon.id }) {
            return selectedLoadout
        }
        return loadouts.first { loadout in
            loadout.slots.contains { $0.itemID == weapon.id }
        }
    }

    private func openWeaponConfiguration(_ weapon: InventoryData.OwnedWeapon,
                                         from loadout: InventoryData.Loadout?) {
        let weaponSlot = loadout?.slots.first { $0.itemID == weapon.id }
        let frameSlot = loadout?.slot(.warframe)
        pushedOwned = weapon
        pushedWarframe = warframe(for: frameSlot)
        pushedWeaponConfigIndex = weaponSlot?.configIndex ?? 0
        pushedWarframeConfigIndex = frameSlot?.configIndex ?? 0
        showConfiguration = true
    }

    private func openEquipmentConfiguration(_ equipment: InventoryData.OwnedEquipment,
                                            initialConfigIndex: Int) {
        pushedEquipment = equipment
        pushedEquipmentConfigIndex = min(
            max(initialConfigIndex, 0), max(equipment.configs.count - 1, 0)
        )
        showEquipmentConfiguration = true
    }

    private func categoryMatches(_ weapon: InventoryData.OwnedWeapon) -> Bool {
        switch category {
        case .all: return true
        case .primary: return weapon.category == "Primary"
        case .secondary: return weapon.category == "Secondary"
        case .melee: return weapon.category == "Melee"
        case .archgun: return weapon.category == "Archgun" || weapon.category == "Archmelee"
        }
    }

    private var filtered: [InventoryData.OwnedWeapon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ownedWeapons.filter { w in
            guard categoryMatches(w) else { return false }
            guard !q.isEmpty else { return true }
            return w.z.lowercased().contains(q)
                || (w.calcName?.lowercased().contains(q) ?? false)
        }
    }

    private var list: some View {
        let rows = filtered
        return LazyVStack(spacing: 0) {
            if inventory.data == nil {
                Text(inventory.failed
                     ? "未能读取军械库数据，下拉刷新或使用右上角「自由计算」。"
                     : "正在读取军械库…")
                    .font(.wfBody)
                    .foregroundColor(inventory.failed ? WFTheme.red : WFTheme.textMuted)
                    .padding(.vertical, WFUI.s4)
            } else if rows.isEmpty {
                Text(ownedWeapons.isEmpty ? "暂无武器数据" : "没有匹配的武器")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
                    .padding(.vertical, WFUI.s5)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, w in
                    Button {
                        openWeaponConfiguration(w, from: contextualLoadout(for: w))
                    } label: {
                        row(w)
                    }
                    .buttonStyle(.plain)
                    if idx < rows.count - 1 {
                        WFHairline().padding(.leading, 68)
                    }
                }
            }
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func catalogEntry(for weapon: InventoryData.OwnedWeapon) -> WeaponEntry? {
        if let name = weapon.calcName,
           let exact = catalog.weapons.first(where: { $0.n.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        return catalogEntry(named: weapon.z) ?? catalogEntry(named: weapon.calcName)
    }

    private func catalogEntry(named rawName: String?) -> WeaponEntry? {
        guard let rawName, !rawName.isEmpty else { return nil }
        let clean = ArsenalItemThumb.stripAnnotation(rawName)
        guard !clean.isEmpty else { return nil }
        if let exact = catalog.weapons.first(where: {
            $0.n.caseInsensitiveCompare(clean) == .orderedSame
                || $0.z.caseInsensitiveCompare(clean) == .orderedSame
        }) {
            return exact
        }
        let targetKey = Self.normalizedCatalogName(clean)
        guard !targetKey.isEmpty else { return nil }
        let candidates = catalog.weapons.filter { entry in
            Self.normalizedCatalogName(entry.n) == targetKey
                || Self.normalizedCatalogName(entry.z) == targetKey
        }
        guard !candidates.isEmpty else { return nil }
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

    private static func normalizedCatalogName(_ raw: String) -> String {
        var text = ArsenalItemThumb.stripAnnotation(raw)
        if text.uppercased().hasPrefix("<ARCHWING>") {
            text = String(text.dropFirst("<ARCHWING>".count))
        }
        for open in [" (", "（"] {
            if let range = text.range(of: open) {
                text = String(text[..<range.lowerBound])
            }
        }
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func canCalculate(_ weapon: InventoryData.OwnedWeapon) -> Bool {
        weapon.calcName != nil && catalogEntry(for: weapon) != nil && !catalog.failed
    }

    private func row(_ w: InventoryData.OwnedWeapon) -> some View {
        let entry = catalogEntry(for: w)
        let supported = canCalculate(w)
        return HStack(spacing: WFUI.s3) {
            WeaponThumb(name: entry?.img, remote: entry?.iconURL, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(w.z)
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(w.categoryLabel)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                    Text("· \(w.configs.count) 套")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    if w.configs.contains(where: { !$0.isExactImport }) {
                        Text("· 缺项")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }
                }
            }

            Spacer(minLength: WFUI.s2)

            if supported {
                Text("可计算")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(WFTheme.cyan.opacity(0.12)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(WFTheme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(supported ? 1 : 0.85)
    }
}

// MARK: - 缩略图

/// 武器图的内存缓存。
///
/// 666 行一次性铺开时，每张 220×220 的 RGBA 解码后接近 200 KB，全解出来是
/// 120 MB 级别——真机上会被系统回收，表现出来就是「列表很卡、图一会儿全没了」。
/// 所以只解码滚到眼前的那几张，解到显示尺寸（40pt × 3 倍 = 120px），按文件名缓存。
final class WeaponIconStore {
    static let shared = WeaponIconStore()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "wf.weapon.icon",
                                      qos: .userInitiated,
                                      attributes: .concurrent)

    private init() {
        cache.countLimit = 320
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func cached(_ name: String) -> UIImage? {
        cache.object(forKey: name as NSString)
    }

    /// 本地包里没有这张图时返回 nil，调用方自己决定要不要走网络。
    func load(_ name: String, maxPixel: CGFloat) async -> UIImage? {
        guard let dir = WeaponCatalog.iconsDir else { return nil }
        return await load(url: dir.appendingPathComponent(name), cacheKey: name, maxPixel: maxPixel)
    }

    func load(url: URL, cacheKey: String, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cached(cacheKey) { return hit }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return await withCheckedContinuation { cont in
            queue.async {
                let image = WeaponIconStore.downsample(url: url, maxPixel: maxPixel)
                if let image = image {
                    let cost = Int(maxPixel * maxPixel * 4)
                    self.cache.setObject(image, forKey: cacheKey as NSString, cost: cost)
                }
                cont.resume(returning: image)
            }
        }
    }

    /// 让 ImageIO 直接解到目标尺寸，而不是先解全图再缩。
    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

/// 武器图。包里带了一份（`ios/DamageData/icons`，构建时从 assets 复制），
/// 优先读本地，读不到再回站点 CDN。两边都没有就画占位块，保证行高不跳。
struct WeaponThumb: View {
    let name: String?
    var localURL: URL? = nil
    let remote: URL?
    let size: CGFloat

    @State private var local: UIImage?
    @State private var tried = false
    @State private var loadedKey = ""

    private var taskKey: String {
        "\(name ?? "")|\(localURL?.path ?? "")|\(remote?.absoluteString ?? "")"
    }

    var body: some View {
        Group {
            if let local = local {
                Image(uiImage: local)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else if tried, let remote = remote {
                // 本地没有这张图才走网络，避免每行都去撞一次 CDN
                AsyncImage(url: remote) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit().padding(2)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WFTheme.panel)
        )
        .task(id: taskKey) {
            if loadedKey != taskKey {
                local = nil
                tried = false
                loadedKey = taskKey
            }
            guard local == nil, !tried else { return }
            let px = size * UIScreen.main.scale
            let image: UIImage?
            if let localURL {
                image = await WeaponIconStore.shared.load(
                    url: localURL,
                    cacheKey: localURL.path,
                    maxPixel: px
                )
            } else if let name = name, !name.isEmpty {
                image = await WeaponIconStore.shared.load(name, maxPixel: px)
            } else {
                image = nil
            }
            if Task.isCancelled { return }
            local = image
            tried = true
        }
    }

    private var placeholder: some View {
        Image(systemName: "scope")
            .font(.system(size: size * 0.36, weight: .light))
            .foregroundColor(WFTheme.textMuted.opacity(0.45))
    }
}

/// 军械库栏位缩略图：武器优先展示 DamageData 武器图，战甲/同伴复用 Asset Catalog 套装图，
/// 无图时显示对应分类的系统图标。
struct ArsenalItemThumb: View {
    let weaponEntry: WeaponEntry?
    let displayName: String?
    let fallbackSymbol: String
    let fallbackColor: Color
    let size: CGFloat

    @ObservedObject private var catalog = WeaponCatalog.shared
    @ObservedObject private var inventory = InventoryFeed.shared

    var body: some View {
        if let entry = resolvedWeaponEntry {
            WeaponThumb(name: entry.img, remote: entry.iconURL, size: size)
        } else if let extraURL = resolvedExtraIconURL {
            WeaponThumb(name: nil, localURL: extraURL, remote: nil, size: size)
        } else if let asset = resolvedSetIcon {
            ItemIcon(asset.local, remote: asset.remote, size: size - 6)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WFTheme.panel)
                )
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(fallbackColor)
                .frame(width: size, height: size)
                .background(fallbackColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var resolvedExtraIconURL: URL? {
        catalog.extraIconURL(forName: displayName)
            ?? catalog.extraIconURL(forName: Self.stripAnnotation(displayName ?? ""))
    }

    private var resolvedWeaponEntry: WeaponEntry? {
        if let weaponEntry { return weaponEntry }
        guard let displayName else { return nil }
        let clean = Self.stripAnnotation(displayName)
        guard !clean.isEmpty else { return nil }
        if let exact = catalog.weapons.first(where: {
            $0.n.caseInsensitiveCompare(clean) == .orderedSame
                || $0.z.caseInsensitiveCompare(clean) == .orderedSame
        }) {
            return exact
        }
        let targetKey = Self.normalizedLookupKey(clean)
        guard !targetKey.isEmpty else { return nil }
        let candidates = catalog.weapons.filter { entry in
            Self.normalizedLookupKey(entry.n) == targetKey
                || Self.normalizedLookupKey(entry.z) == targetKey
        }
        guard !candidates.isEmpty else { return nil }
        let preferredSuffixes = ["(大气)", "(atmo-mode)", "(突击步枪)", "(rifle)", "(archwing)"]
        return candidates.first(where: { entry in
            let zn = entry.z.lowercased()
            let nn = entry.n.lowercased()
            return preferredSuffixes.contains { zn.contains($0) || nn.contains($0) }
        }) ?? candidates.first
    }

    private static func normalizedLookupKey(_ raw: String) -> String {
        var text = stripAnnotation(raw)
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

    private var resolvedSetIcon: (local: String?, remote: String?)? {
        guard let displayName else { return nil }
        let clean = Self.stripAnnotation(displayName)
        guard !clean.isEmpty else { return nil }

        if let matchedSet = inventory.data?.sets.first(where: {
            $0.zh.caseInsensitiveCompare(clean) == .orderedSame
                && (!($0.i ?? "").isEmpty || !($0.u ?? "").isEmpty)
        }) {
            return (matchedSet.i, matchedSet.u)
        }

        let slug = clean.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            + "_set"
        if UIImage(named: slug) != nil {
            return (slug, nil)
        }
        return nil
    }

    static func stripAnnotation(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["（", "("] {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
