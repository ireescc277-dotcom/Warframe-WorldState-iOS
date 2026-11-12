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
                    Text("空计算器")
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
            return inventory.fetching ? "正在读取背包快照…" : "尚未取得背包快照"
        }
        if page == .inventory {
            return weaponSubtitle
        }
        if let loadout = selectedLoadout {
            let marked = loadout.snapshotMarkedActive ? " · 快照标记" : ""
            return "配置 \(loadout.name)\(marked) · 进入装备后查看 A/B/C"
        }
        return "军械库配置由账号快照导入"
    }

    private var weaponSubtitle: String {
        if catalog.failed {
            return "背包 \(ownedWeapons.count) 把 · 计算器数据不可用"
        }
        return "背包 \(ownedWeapons.count) 把 · 先进入配置页，再预填伤害计算"
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
                     ? "没有可用的背包快照。下拉重试；装备列表仍可在有快照后使用。"
                     : "正在读取背包快照…")
                    .font(.wfBody)
                    .foregroundColor(inventory.failed ? WFTheme.red : WFTheme.textMuted)
                    .padding(.vertical, WFUI.s4)
            } else {
                VStack(alignment: .leading, spacing: WFUI.s4) {
                    Text("普通军械库、同伴和 Archwing 是账号快照中的三组独立预设；物品轮是账号级条目。这里按游戏军械库分区展示，不虚构它们之间的预设关联。")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                        .padding(.horizontal, WFUI.s1)
                    normalLoadoutSection
                    companionLoadoutSection
                    gearWheelSection
                    archwingLoadoutSection
                }
            }
        }
    }

    private var normalLoadoutSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("战甲与武器", trailing: "普通军械库")
            if let loadout = selectedLoadout {
                loadoutPicker(
                    normalLoadouts,
                    selection: $selectedLoadoutID,
                    title: loadout.name,
                    subtitle: "普通军械库配置 · 来自账号快照",
                    symbol: "square.grid.2x2"
                )
                loadoutCard(loadout)
            } else {
                sourceEmptyCard("账号快照没有普通军械库预设。")
            }
        }
    }

    private var companionLoadoutSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("同伴", trailing: "独立预设")
            if let loadout = selectedCompanionLoadout {
                loadoutPicker(
                    companionLoadouts,
                    selection: $selectedCompanionLoadoutID,
                    title: loadout.name,
                    subtitle: "同伴预设 · 来自账号快照",
                    symbol: "hare"
                )
                loadoutCard(loadout)
            } else if let companion = ownedCompanions.first {
                Text("账号快照没有同伴预设；下方显示已导入的第一个同伴配置。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                equipmentFallbackRow(companion, role: .companion)
            } else {
                sourceEmptyCard("账号快照没有已导入的同伴或同伴预设。")
            }
        }
    }

    private var gearWheelSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("物品", trailing: "账号级装备轮")
            Text("顺序来自快照的 EquippedGear。数量只在同一快照的消耗品堆栈有记录时显示。")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            if equippedGear.isEmpty {
                sourceEmptyCard("账号快照没有装备轮条目。")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 7)], spacing: 7) {
                    ForEach(equippedGear) { gear in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("槽位 \(gear.slot + 1)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(WFTheme.textMuted)
                            Text(gear.name)
                                .font(.wfLabel)
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(2)
                            Text(gear.count.map { "数量 \($0)" } ?? "无堆栈数量记录")
                                .font(.system(size: 10))
                                .foregroundColor(gear.count == nil ? WFTheme.textMuted : WFTheme.gold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                        .padding(8)
                        .background(WFUI.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .wfCardStyle()
    }

    private var archwingLoadoutSection: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            WFSectionHeader("Archwing", trailing: "独立预设")
            if let loadout = selectedArchwingLoadout {
                loadoutPicker(
                    archwingLoadouts,
                    selection: $selectedArchwingLoadoutID,
                    title: loadout.name,
                    subtitle: "Archwing 预设 · 来自账号快照",
                    symbol: "airplane"
                )
                loadoutCard(loadout)
            } else if let archwing = ownedArchwings.first {
                Text("账号快照没有 Archwing 预设；下方显示已导入的第一个 Archwing 配置。")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                equipmentFallbackRow(archwing, role: .archwing)
            } else {
                sourceEmptyCard("账号快照没有已导入的 Archwing 或 Archwing 预设。")
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

    private func loadoutPicker(_ choices: [InventoryData.Loadout],
                               selection: Binding<String?>,
                               title: String,
                               subtitle: String,
                               symbol: String) -> some View {
        Menu {
            ForEach(choices) { loadout in
                Button(loadoutMenuLabel(loadout)) {
                    selection.wrappedValue = loadout.id
                }
            }
        } label: {
            HStack(spacing: WFUI.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WFTheme.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textPrimary)
                    Text(subtitle)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
            }
            .padding(.horizontal, WFUI.s3)
            .padding(.vertical, 10)
            .background(WFUI.surface)
            .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func loadoutMenuLabel(_ loadout: InventoryData.Loadout) -> String {
        var labels = [loadout.name]
        if loadout.isFavorite { labels.append("收藏") }
        if loadout.snapshotMarkedActive { labels.append("快照标记") }
        return labels.joined(separator: " · ")
    }

    private func loadoutCard(_ loadout: InventoryData.Loadout) -> some View {
        let roles = roles(for: loadout.kind)
        return VStack(spacing: 0) {
            ForEach(Array(roles.enumerated()), id: \.element) { index, role in
                loadoutEquipmentRow(role, slot: loadout.slot(role), in: loadout)
                if index < roles.count - 1 {
                    WFHairline().padding(.leading, 48)
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
        let config = slot?.configLabel.map { "配置 \($0)" } ?? "没有配置记录"
        let sourceDetail = slot?.sourceIssue
            ?? (slot?.isHidden == true ? "\(config) · 快照标记为隐藏" : config)
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
                Image(systemName: symbol(for: role))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color(for: role))
                    .frame(width: 28, height: 28)
                    .background(color(for: role).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.label)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    Text(name)
                        .font(.wfTitle)
                        .foregroundColor(isAvailable ? WFTheme.textPrimary : WFTheme.textMuted)
                        .lineLimit(1)
                    Text(sourceDetail)
                        .font(.wfLabel)
                        .foregroundColor(slot?.sourceIssue == nil ? WFTheme.textSecondary : WFTheme.gold)
                        .lineLimit(1)
                }
                Spacer(minLength: WFUI.s2)
                Image(systemName: isAvailable ? "chevron.right" : "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
            }
            .padding(.horizontal, WFUI.s3)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.58)
    }

    private func equipmentFallbackRow(_ equipment: InventoryData.OwnedEquipment,
                                      role: InventoryData.Loadout.Slot.Role) -> some View {
        Button {
            openEquipmentConfiguration(equipment, initialConfigIndex: 0)
        } label: {
            HStack(spacing: WFUI.s3) {
                Image(systemName: symbol(for: role))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color(for: role))
                    .frame(width: 28, height: 28)
                    .background(color(for: role).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.label)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    Text(equipment.z)
                        .font(.wfTitle)
                        .foregroundColor(WFTheme.textPrimary)
                    Text("背包中已导入 · (equipment.configs.count) 套配卡")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                }
                Spacer(minLength: WFUI.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
            }
            .padding(.horizontal, WFUI.s3)
            .padding(.vertical, 10)
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
                     ? "没有可用的背包快照。下拉重试；空计算器仍可手动选武器。"
                     : "正在读取背包快照…")
                    .font(.wfBody)
                    .foregroundColor(inventory.failed ? WFTheme.red : WFTheme.textMuted)
                    .padding(.vertical, WFUI.s4)
            } else if rows.isEmpty {
                Text(ownedWeapons.isEmpty ? "这份背包快照没有武器实例。" : "没有匹配的背包武器")
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
                        WFHairline().padding(.leading, 56)
                    }
                }
            }
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func catalogEntry(for weapon: InventoryData.OwnedWeapon) -> WeaponEntry? {
        guard let name = weapon.calcName else { return nil }
        return catalog.weapons.first(where: { $0.n == name })
    }

    private func canCalculate(_ weapon: InventoryData.OwnedWeapon) -> Bool {
        weapon.calcName != nil && catalogEntry(for: weapon) != nil && !catalog.failed
    }

    private func row(_ w: InventoryData.OwnedWeapon) -> some View {
        let entry = catalogEntry(for: w)
        let supported = canCalculate(w)
        return HStack(spacing: WFUI.s3) {
            WeaponThumb(name: entry?.img, remote: entry?.iconURL, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(w.z)
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(w.categoryLabel)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                    Text("\(w.configs.count) 套配卡")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    if w.configs.contains(where: { !$0.isExactImport }) {
                        Text("有未导入槽位")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }
                }
            }

            Spacer(minLength: WFUI.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text(supported ? "配置 · 可计算" : "查看配置")
                    .font(.wfLabel)
                    .foregroundColor(supported ? WFTheme.cyan : WFTheme.textMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .opacity(supported ? 1 : 0.82)
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
        if let hit = cached(name) { return hit }
        guard let dir = WeaponCatalog.iconsDir else { return nil }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return await withCheckedContinuation { cont in
            queue.async {
                let image = WeaponIconStore.downsample(url: url, maxPixel: maxPixel)
                if let image = image {
                    let cost = Int(maxPixel * maxPixel * 4)
                    self.cache.setObject(image, forKey: name as NSString, cost: cost)
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
    let remote: URL?
    let size: CGFloat

    @State private var local: UIImage?
    @State private var tried = false

    var body: some View {
        Group {
            if let local = local {
                Image(uiImage: local)
                    .resizable()
                    .scaledToFit()
            } else if tried, let remote = remote {
                // 本地没有这张图才走网络，避免每行都去撞一次 CDN
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
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WFTheme.panel)
        )
        .task(id: name) {
            guard local == nil, !tried else { return }
            guard let name = name, !name.isEmpty else {
                tried = true
                return
            }
            let px = size * UIScreen.main.scale
            let image = await WeaponIconStore.shared.load(name, maxPixel: px)
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
